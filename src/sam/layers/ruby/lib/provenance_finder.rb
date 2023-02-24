# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'aws-sdk-cognitoidentityprovider'

require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'

# -------------------------------------------------------------------------------------------
# Provenance Helper
#
# Shared helper methods for Lambdas that retrieve the Provenance item from the Dynamo Table
# -------------------------------------------------------------------------------------------
class ProvenanceFinder
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Get the Provenance item for the Lambda :event
  #
  # Expecting the :claims hash from the requestContext[:authorizer] portion of the :event.
  # It should look something like this:
  #  {
  #    "sub": "abcdefghijklmnopqrstuvwxyz",
  #    "token_use": "access",
  #    "scope": "https://auth.dmphub-dev.cdlib.org/dev.write",
  #    "auth_time": "1675895546",
  #    "iss": "https://cognito-idp.us-west-2.amazonaws.com/us-west-A_123456",
  #    "exp": "Wed Feb 08 22:42:26 UTC 2023",
  #    "iat": "Wed Feb 08 22:32:26 UTC 2023",
  #    "version": "2",
  #    "jti": "5d3be8a7-c595-1111-yyyy-xxxxxxxxxx",
  #    "client_id": "abcdefghijklmnopqrstuvwxyz"
  #  }
  # -------------------------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def provenance_from_lambda_cotext(identity:)
    source = 'ProvenanceHelper.provenance_from_lambda_cotext'
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } unless identity.is_a?(Hash) &&
                                                                      !identity['iss'].nil? &&
                                                                      !identity['client_id'].nil?

    client_name = client_id_to_name(claim: identity)
    p_key = "#{KeyHelper::PK_PROVENANCE_PREFIX}#{client_name}"
    response = @client.get_item(
      {
        table_name: @table,
        key: { PK: p_key, SK: KeyHelper::SK_PROVENANCE_PREFIX },
        consistent_read: false,
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    log_message(source: source, message: 'Provenance from Lambda Context', details: response[:items].first) if @debug
    return { status: 404, error: Messages::MSG_PROVENANCE_NOT_FOUND } if response[:item].nil? ||
                                                                         response[:item].empty?

    { status: 200, items: [response[:item]] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(
      source: source, message: e.message, details: (["INPUT: #{identity.inspect}"] << e.backtrace).flatten
    )
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Fetch the Provenance by it's PK
  # rubocop:disable Metrics/AbcSize
  def provenance_from_pk(p_key:)
    source = "ProvenanceHelper.provenance_from_pk - looking for #{p_key}"
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if p_key.nil?

    p_key = "#{KeyHelper::PK_PROVENANCE_PREFIX}#{p_key}" unless p_key.to_s.start_with?(KeyHelper::PK_PROVENANCE_PREFIX)

    response = @client.get_item(
      {
        table_name: @table,
        key: { PK: p_key, SK: KeyHelper::SK_PROVENANCE_PREFIX },
        consistent_read: false,
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    log_message(source: source, message: 'Provenance from PK', details: response[:items].first) if @debug
    return { status: 404, error: Messages::MSG_PROVENANCE_NOT_FOUND } if response[:item].nil? ||
                                                                         response[:item].empty?

    { status: 200, items: [response[:item]] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message, details: e.backtrace)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize

  # Method to fetch the client's name from the Cognito UserPool based on the client_id
  # rubocop:disable Metrics/AbcSize
  def client_id_to_name(claim:)
    return nil if claim.nil? || !claim.is_a?(Hash) || claim['iss'].nil? || claim['client_id'].nil?

    user_pool_id = claim['iss'].split('/').last
    source = "ProvenanceHelper.client_id_to_name - UserPool: #{user_pool_id}"
    client_id = claim['client_id']
    client = Aws::CognitoIdentityProvider::Client.new(region: ENV.fetch('AWS_REGION', nil))
    resp = client.describe_user_pool_client({ user_pool_id: user_pool_id, client_id: client_id })
    name = resp&.user_pool_client&.client_name&.downcase
    log_message(source: SOURCE, message: "Found provenance #{name} for Cognito id #{client_id}") if @debug
    name
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message, details: e.backtrace)
    nil
  end
  # rubocop:enable Metrics/AbcSize
end
