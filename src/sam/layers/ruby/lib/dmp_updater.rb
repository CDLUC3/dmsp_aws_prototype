# frozen_string_literal: true

require 'aws-sdk-dynamodb'

require 'dmp_helper'
require 'dmp_versioner'
require 'event_publisher'
require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'
require 'validator'

# -------------------------------------------------------------------------
# Dynamo Table Helper for updating DMP items
#
# Shared helper methods for Lambdas that interact with the DynamoDB Table
# -------------------------------------------------------------------------
class DmpUpdater
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Update a record in the table
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # -------------------------------------------------------------------------
  def update_dmp(p_key:, json: {})
    json = Validator.parse_json(json: json)&.fetch('dmp', {})
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if json.nil? || p_key.nil?

    # Fail if the provenance is not defined
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if !@provenance.is_a?(Hash) ||
                                                                  @provenance['PK'].nil?
    # Verify that the JSON is for the same DMP in the PK
    dmp_id = json.fetch('dmp_id', {})
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } unless KeyHelper.dmp_id_to_pk(json: dmp_id) == p_key

    # Add the DMPHub specific attributes
    dmp = DmpHelper.annotate_dmp(provenance: @provenance, json: json, p_key: p_key)

    # Only allow this if the provenance is the owner of the DMP!
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if dmp['dmphub_provenance_id'] != @provenance['PK']
    # Make sure they're not trying to update a historical copy of the DMP
    return { status: 405, error: Messages::MSG_DMP_NO_HISTORICALS } if dmp['SK'] != KeyHelper::DMP_LATEST_VERSION
    # Don't allow tombstoned DMPs to be updated
    return { status: 400, error: Messages::MSG_DMP_NOT_FOUND } if dmp['SK'] == KeyHelper::DMP_TOMBSTONE_VERSION
    # Don't continue if nothing has changed!
    return { status: 200, error: NO_CHANGE, items: [dmp] } if DmpHelper.dmps_equal?(dmp_a: dmp, dmp_b: json)

    # Version the current 'latest' and update the new version with a reference to the prior
    result = DmpVersioner.process(
      p_key: p_key, dmp: json, provenance: @provenance, client: @client, table: @table, debug: @debug
    )
    return result unless result[:status] == 200

    p 'JSON AFTER VERSIONING:' if @debug
    p result[:items].first if @debug

    # Since the PK and SK are the same as the original record, this will just replace eveything
    response = @client.put_item({
      table_name: @table, item: result[:items].first, return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' }
    )
    return { status: 500, error: Messages::MSG_SERVER_ERROR } unless response.successful?

    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    response = finder.find_dmp_by_pk(p_key: p_key, s_key: KeyHelper::DMP_LATEST_VERSION)
    return response unless response[:status] == 200

    # Send the updates to EZID, notify the provenance and download the PDF if applicable
    _post_process(json: dmp)

    { status: 200, items: response[:items] }
  rescue Aws::DynamoDB::Errors::DuplicateItemException
    { status: 405, error: Messages::MSG_DMP_EXISTS }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: "DmpUpdater.update_dmp - PK #{p_key}", message: e.message,
                        details: ([@provenance, json.inspect] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # ------------------------------------------------------------------------------------
  # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS MODULE
  # ------------------------------------------------------------------------------------

  # Once the DMP has been updated, we need to register it's DMP ID and download any
  # PDF if applicable
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def _post_process(json:)
    return false if json.nil?

    # Indicate whether or not the updater is the provenance system
    json['dmphub_updater_is_provenance'] = @provenance['PK'] == json['dmphub_provenance_id']
    # Publish the change to the EventBridge
    EventPublisher.publish(source: 'DmpUpdater', dmp: json)
    true
  end
  # rubocop:enable Metrics/AbcSize
end
