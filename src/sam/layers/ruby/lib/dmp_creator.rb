# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'securerandom'

require 'dmp_helper'
require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'
require 'validator'

# -------------------------------------------------------------------------
# Dynamo Table Helper for creating new DMP items
#
# Shared helper methods for Lambdas that interact with the DynamoDB Table
# -------------------------------------------------------------------------
class DmpCreator
  attr_accessor :provenance, :can_skip_preregister,
                :table, :client, :debug,
                :dmp_id_shoulder, :dmp_id_base_url

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @can_skip_preregister = @provenance['seedingWithLiveDmpIds'].to_s.downcase.strip == 'true'
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)

    # Only call SSM once for these
    @dmp_id_base_url = SsmReader.get_ssm_value(key: SsmReader::DMP_ID_BASE_URL)
    @dmp_id_shoulder = SsmReader.get_ssm_value(key: SsmReader::DMP_ID_SHOULDER)
  end

  # Add a record to the table
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def create_dmp(json: {})
    json = Validator.parse_json(json: json)&.fetch('dmp', {})
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if json.nil?

    # Fail if the provenance is not defined
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if !@provenance.is_a?(Hash) ||
                                                                  @provenance['PK'].nil?

    # Try to find it first and Fail if found
    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    result = finder.find_dmp_by_json(json: json)
    return result if result[:status] == 500
    return { status: 400, error: Messages::MSG_DMP_EXISTS } if result.fetch(:items, []).any?

    p_key = _preregister_dmp_id(finder: finder, json: json) if p_key.nil?
    return { status: 500, error: Messages::MSG_DMP_NO_DMP_ID } if p_key.nil?

    # Add the DMPHub specific attributes and then save
    json = DmpHelper.annotate_dmp(provenance: @provenance, json: json, p_key: p_key)

    # Create the item
    @client.put_item({ table_name: @table, item: json, return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' })
    # Should probably abort here if it fails ... not sure what that looks like yet

    # Fetch and return the newly created record
    response = finder.find_dmp_by_pk(p_key: p_key, s_key: KeyHelper::DMP_LATEST_VERSION)
    return response unless response[:status] == 200

    # Send SNS notifications for post processing tasks
    _post_process(provenance: provenance, p_key: p_key, json: json)

    { status: 201, items: response[:items] }
  rescue Aws::DynamoDB::Errors::DuplicateItemException
    { status: 405, error: Messages::MSG_DMP_EXISTS }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: 'DmpCreator.create_dmp', message: e.message,
                        details: ([@provenance, json.inspect] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # -------------------------------------------------------------------------
  # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS CLASS
  # -------------------------------------------------------------------------

  # Preassign a DMP ID that will later be sent to the DOI minting authority
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def _preregister_dmp_id(finder:, json:)
    # Use the specified DMP ID if the provenance has permission
    existing = json.fetch('dmp_id', {})
    id = existing['identifier'].gsub(%r{https?://}, KeyHelper::PK_DMP_PREFIX) unless existing.nil? ||
                                                                                     existing['identifier'].nil?
    return id if @can_skip_preregister && existing['type'].downcase == 'doi' &&
                 !_dmp_id_exists?(finder: finder, hash: existing)

    dmp_id = ''
    counter = 0
    while dmp_id == '' && counter <= 10
      prefix = "#{@dmp_id_shoulder}#{SecureRandom.hex(2).upcase}#{SecureRandom.hex(2)}"
      dmp_id = prefix unless _dmp_id_exists?(finder: finder, hash: { type: 'doi', identifier: prefix }.to_json)
      counter += 1
    end
    # Something went wrong and it was unable to identify a unique id
    return nil if counter >= 10

    url = @dmp_id_base_url.gsub(%r{https?://}, '')
    "#{KeyHelper::PK_DMP_PREFIX}#{url.end_with?('/') ? url : "#{url}/"}#{dmp_id}"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Once the DMP has been created, we need to register it's DMP ID and download any
  # PDF if applicable
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def _post_process(provenance:, p_key:, json:)
    return false if p_key.nil? || p_key.to_s.strip.empty?

    # Register the DMP ID with EZID if the provenance is not seeding with live DMP IDs
    unless provenance.fetch('seedingWithLiveDmpIds', 'false').to_s.downcase == 'true'
      Aws::SNS::Client.new.publish(
        topic_arn: SsmReader.get_ssm_value(key: SsmReader::SNS_PUBLISH_TOPIC),
        subject: "DmpCreator - register DMP ID - #{p_key}",
        message: { action: 'create', provenance: @provenance['PK'], dmp: p_key }.to_json
      )
    end
    return true unless json.is_a?(Hash) && json.fetch('dmproadmap_related_identifiers', []).any?
    # If the privacy setting is not 'public', then do not download the PDF
    return true unless json.fetch('dmproadmap_privacy', 'private').to_s.downcase.strip == 'public'

    dmp_urls = json['dmproadmap_related_identifiers'].select do |identifier|
      identifier['work_type'] == 'output_management_plan' && identifier['descriptor'] == 'is_metadata_for'
    end
    return true if dmp_urls.empty?

    Aws::SNS::Client.new.publish(
      topic_arn: SsmReader.get_ssm_value(key: SsmReader::SNS_DOWNLOAD_TOPIC),
      subject: "DmpCreator - fetch DMP document - #{p_key}",
      message: { provenance: @provenance['PK'], dmp: p_key, location: dmp_urls.first['identifier'] }.to_json
    )
    true
  end
  # rubocop:enable Metrics/AbcSize

  # See if the DMP Id exists
  # -------------------------------------------------------------------------
  def _dmp_id_exists?(finder:, hash:)
    return false unless hash.is_a?(Hash) && hash['type'].downcase.strip == 'doi'

    dmp_id = hash['identifier'].to_s.strip
    return false if dmp_id.empty?

    resp = finder.find_dmp_by_pk(p_key: KeyHelper.append_pk_prefix(dmp: dmp_id))
    resp[:status] == 200
  end
end
