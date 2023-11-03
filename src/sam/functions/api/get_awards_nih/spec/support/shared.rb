# frozen_string_literal: true

require 'ostruct'

# Mock AWS Lambda Context
AwsContext = Struct.new(
  'AwsContext', :function_name, :function_version, :invoked_function_arn,
  :memory_limit_in_mb, :aws_request_id, :log_group_name, :log_stream_name,
  :deadline_ms, :identity, :client_context
)

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

# Mock URL
def mock_url
  'http://example.com'
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

def aws_context(args: {})
  # see: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
  AwsContext.new(
    args.fetch(:function_name, ''),
    args.fetch(:function_version, ''),
    args.fetch(:invoked_function_arn, ''),
    args.fetch(:memory_limit_in_mb, ''),
    args.fetch(:aws_request_id, ''),
    args.fetch(:log_group_name, ''),
    args.fetch(:log_stream_name, ''),
    args.fetch(:deadline_ms, ''),
    args.fetch(:identity, {}),
    args.fetch(:client_context, {})
  )
end

# rubocop:disable Metrics/MethodLength
def request_context(args: {})
  context = {
    accountId: '123456789012',
    resourceId: '123456',
    stage: 'test',
    requestId: 'c6af9ac6-7b61-11e6-9a41-93e8deadbeef',
    requestTime: '09/Apr/2015:12:34:56 +0000',
    requestTimeEpoch: 1_428_582_896_000,
    identity: {
      cognitoIdentityPoolId: 'null',
      accountId: 'null',
      cognitoIdentityId: 'null',
      caller: 'null',
      accessKey: 'null',
      sourceIp: '127.0.0.1',
      cognitoAuthenticationType: 'null',
      cognitoAuthenticationProvider: 'null',
      userArn: 'null',
      userAgent: 'Custom User Agent String',
      user: 'null'
    },
    path: '/prod/path/to/resource',
    resourcePath: '/{proxy+}',
    httpMethod: 'POST',
    apiId: '1234567890',
    protocol: 'HTTP/1.1'
  }

  JSON.parse({ requestContext: context.merge(args) }.to_json)
end
# rubocop:enable Metrics/MethodLength

# rubocop:disable Metrics/MethodLength
def headers(args: {})
  hash = {
    'Content-Type': 'application/json',
    'User-Agent': 'dmp-hub-sam tests',
    'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Encoding' => 'gzip, deflate, sdch',
    'Accept-Language' => 'en-US,en;q=0.8',
    'Cache-Control' => 'max-age=0',
    'CloudFront-Forwarded-Proto' => 'https',
    'CloudFront-Is-Desktop-Viewer' => 'true',
    'CloudFront-Is-Mobile-Viewer' => 'false',
    'CloudFront-Is-SmartTV-Viewer' => 'false',
    'CloudFront-Is-Tablet-Viewer' => 'false',
    'CloudFront-Viewer-Country' => 'US',
    'Host' => '1234567890.execute-api.us-east-1.amazonaws.com',
    'Upgrade-Insecure-Requests' => '1',
    'Via' => '1.1 08f323deadbeefa7af34d5feb414ce27.cloudfront.net (CloudFront)',
    'X-Amz-Cf-Id' => 'cDehVQoZnx43VYQb9j2-nvCh-9z396Uhbp027Y2JvkCPNLmGJHqlaA==',
    'X-Forwarded-For' => '127.0.0.1, 127.0.0.2',
    'X-Forwarded-Port' => '443',
    'X-Forwarded-Proto' => 'https'
  }
  hash.merge(args)
end
# rubocop:enable Metrics/MethodLength
