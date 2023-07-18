# frozen_string_literal: true

require 'ostruct'

# Mock AWS SSM Parameter Store Resources
SsmClient = Struct.new('SsmClient', :get_parameter)
SsmParameter = Struct.new('SsmParameter', :parameter)
SsmValue = Struct.new('SsmValue', :value)

# Mock AWS SNS Topic Resources
SnsClient = Struct.new('SnsClient', :publish)

def mock_ssm(value:, success: true)
  ssm_client = SsmClient.new
  ssm_parameter = SsmParameter.new(SsmValue.new(value))

  allow(Aws::SSM::Client).to receive(:new).and_return(ssm_client)
  allow(ssm_client).to receive(:get_parameter).and_return(ssm_parameter) if success
  allow(ssm_client).to receive(:get_parameter).and_raise(aws_error) unless success
  ssm_client
end

def mock_sns(success: true)
  sns_client = SnsClient.new

  allow(Aws::SNS::Client).to receive(:new).and_return(sns_client)
  allow(sns_client).to receive(:publish).and_return(true) if success
  allow(sns_client).to receive(:publish).and_raise(aws_error) unless success
  sns_client
end

# Mock URL
def mock_url
  'http://example.com'
end

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

def aws_event(args: {}, header_args: {}, request_context_args: {})
  event = {
    headers: headers(args: header_args),
    httpMethod: 'GET',
    isBase64Encoded: false,
    path: '/dmps/',
    pathParameters: {},
    queryStringParameters: {},
    requestContext: request_context(args: request_context_args),
    resource: '/dmps',
    version: '1.0'
  }
  JSON.parse(event.merge(args).to_json)
end

# rubocop:disable Metrics/MethodLength
def aws_event_bridge_event(args: {})
  details = {
    PK: 'DMP#doi.org/10.12345/ABC123',
    SK: 'VERSION#latest',
    dmphub_provenance_id: 'PROVENANCE#foo',
    dmproadmap_links: {
      download: 'https://example.com/api/dmps/12345.pdf'
    },
    dmphub_updater_is_provenance: false
  }
  details = details.merge(args['detail']) unless args['detail'].nil?

  event = {
    version: '0',
    id: 'abcd123-xyz1234-gg33-lkjh-abcyyz123789',
    'detail-type': args.fetch(:detail_type, 'DMP change'),
    source: args.fetch(:source, 'dmphub-dev.cdlib.org:lambda:event_publisher'),
    account: '1234567890',
    time: Time.now.iso8601,
    region: 'us-west-2',
    resources: args.fetch(:resources, []),
    detail: details
  }
  JSON.parse(event.merge(args).to_json)
end
# rubocop:enable Metrics/MethodLength

# Helper function that compares 2 hashes regardless of the order of their keys
def compare_hashes(hash_a: {}, hash_b: {})
  a_keys = hash_a.keys.sort { |a, b| a <=> b }
  b_keys = hash_b.keys.sort { |a, b| a <=> b }
  return false unless a_keys == b_keys

  valid = true
  a_keys.each { |key| valid = false unless hash_a[key] == hash_b[key] }
  valid
end
