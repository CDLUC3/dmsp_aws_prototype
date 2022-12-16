# frozen_string_literal: true

require 'aws-sdk-dynamodb'

require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'

# -------------------------------------------------------------------------
# Dynamo Table Helper for deleting/tombstoning DMP items
#
# Shared helper methods for Lambdas that interact with the DynamoDB Table
# -------------------------------------------------------------------------
class DmpDeleter
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Delete/Tombstone a record in the table
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # -------------------------------------------------------------------------
  def delete_dmp(p_key:)
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if p_key.nil?

    # Fail if the provenance is not defined
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if !@provenance.is_a?(Hash) ||
                                                                  @provenance['PK'].nil?

    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    result = finder.find_dmp_by_pk(p_key: p_key)
    return result unless result[:status] == 200

    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if result[:items].nil? || result[:items].empty?

    dmp = result[:items].first['dmp']
    # Only allow this if the provenance is the owner of the DMP!
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if dmp['dmphub_provenance_id'] != @provenance['PK']
    # Make sure they're not trying to update a historical copy of the DMP
    return { status: 405, error: Messages::MSG_DMP_NO_HISTORICALS } if dmp['SK'] != KeyHelper::DMP_LATEST_VERSION

    dmp['SK'] = KeyHelper::DMP_TOMBSTONE_VERSION
    dmp['deletion_date'] = Time.now.iso8601
    dmp['title'] = "OBSOLETE: #{dmp['title']}"

    # Create the Tombstone record
    response = @client.put_item({ table_name: @table, item: dmp, return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' })
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } unless response.successful?

    # Delete the Latest record
    response = @client.delete_item({
                                     table_name: @table, key: { PK: dmp['PK'], SK: KeyHelper::SK_DMP_PREFIX }
                                   })

    # Notify EZID about the removal
    _post_process(p_key: dmp['PK'])

    # We should abort here if we can determine that it did not succeed
    { status: 200, items: [JSON.parse({ dmp: dmp }.to_json)] } if response.successful?
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: "DmpDeleter.delete_dmp - PK #{p_key}", message: e.message,
                        details: ([@provenance] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Once the DMP has been created, we need to register it's DMP ID and download any
  # PDF if applicable
  # -------------------------------------------------------------------------
  def _post_process(p_key:)
    return false if p_key.nil? || p_key.to_s.strip.empty?

    Aws::SNS::Client.new.publish(
      topic_arn: SsmReader.get_ssm_value(key: SsmReader::SNS_PUBLISH_TOPIC),
      subject: "DmpDeleter - tombstone DMP ID - #{p_key}",
      message: { action: 'tombstone', provenance: @provenance['PK'], dmp: p_key }.to_json
    )
  end
end
