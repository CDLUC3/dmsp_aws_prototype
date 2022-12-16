# frozen_string_literal: true

require 'aws-sdk-dynamodb'

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
  # Expecting the :identity hash from the :event. It should look like this:
  #  "identity": {
  #    "cognitoIdentityPoolId": "foo",
  #    "cognitoIdentityId": "bar",
  #    "apiKey": "12345",
  #    "principalOrgId": "1111",
  #    "cognitoAuthenticationType": "test",
  #    "userArn": "arn:ergqegq345g",
  #    "apiKeyId": "00000",
  #    "userAgent": "aws-internal/3 aws-sdk-java/1.12.239 ...",
  #    "accountId": "12345667890",
  #    "caller": "abcd1234",
  #    "sourceIp": "10.0.0.1",
  #    "accessKey": "abcdefg12345",
  #    "cognitoAuthenticationProvider": "foo",
  #    "user": "abcd1234",
  #    "domainName": "example.com",
  #    "apiId": "abcdefghijk9090"
  #  }
  # -------------------------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def provenance_from_lambda_cotext(identity:)
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } unless identity.is_a?(Hash) &&
                                                                      !identity['cognitoIdentityId'].nil?

    p_key = "#{KeyHelper::PK_PROVENANCE_PREFIX}#{identity['cognitoIdentityId']}"
    response = @client.get_item(
      {
        table_name: @table,
        key: { PK: p_key, SK: KeyHelper::SK_PROVENANCE_PREFIX },
        consistent_read: false,
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    return { status: 404, error: Messages::MSG_PROVENANCE_NOT_FOUND } if response[:item].nil? ||
                                                                         response[:item].empty?

    { status: 200, items: [response[:item]] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(
      source: "LambdaLayer - ProvenanceHelper.provenance_from_lambda_cotext - looking for #{p_key}",
      message: e.message, details: (["INPUT: #{identity.inspect}"] << e.backtrace).flatten
    )
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize

  # Fetch the Provenance by it's PK
  def provenance_from_pk(p_key:)
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
    return { status: 404, error: Messages::MSG_PROVENANCE_NOT_FOUND } if response[:item].nil? ||
                                                                         response[:item].empty?

    { status: 200, items: [response[:item]] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(
      source: "LambdaLayer - ProvenanceHelper.provenance_from_pk - looking for #{p_key}",
      message: e.message, details: e.backtrace
    )
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
end
