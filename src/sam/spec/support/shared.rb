# frozen_string_literal: true

require 'ostruct'

# Mock AWS SSM Parameter Store Resources
SsmClient = Struct.new('SsmClient', :get_parameter)
SsmParameter = Struct.new('SsmParameter', :parameter)
SsmValue = Struct.new('SsmValue', :value)

# Mock AWS SNS Topic Resources
SnsClient = Struct.new('SnsClient', :publish)

# Mock AWS DynamoDB Table Resources
DynamoClient = Struct.new('DynamoClient', :update_item, :put_item, :get_item, :delete_item, :query, :scan)
# Dynamo returns an array in all cases but :get_item which returns a hash.
DynamoResponse = Struct.new('DynamoResponse', :items, :item, :successful?)
DynamoItem = Struct.new('DynamoItem', :item)

# Mock S3 Resources
S3Client = Struct.new('S3Client', :put_object)
S3Response = Struct.new('S3Response', :successful?)

# Cognito Resources
CognitoClient = Struct.new('CognitoClient', :describe_user_pool_client)
CognitoResponse = Struct.new('CognitoResponse', :user_pool_client)
CognitoUserPool = Struct.new('CognitoUserPool', :client_name)

# Mock AWS Lambda Context
AwsContext = Struct.new(
  'AwsContext', :function_name, :function_version, :invoked_function_arn,
  :memory_limit_in_mb, :aws_request_id, :log_group_name, :log_stream_name,
  :deadline_ms, :identity, :client_context
)

# Mock HTTParty
HttpartyResponse = Struct.new('HTTPartyResponse', :code, :body)

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

# rubocop:disable Metrics/AbcSize
def mock_httparty(code: 200, body: '')
  resp = HttpartyResponse.new
  allow(resp).to receive(:code).and_return(code)
  allow(resp).to receive(:body).and_return(body.to_s)
  allow(HTTParty).to receive(:delete).and_return(resp)
  allow(HTTParty).to receive(:get).and_return(resp)
  allow(HTTParty).to receive(:post).and_return(resp)
  allow(HTTParty).to receive(:put).and_return(resp)
  resp
end
# rubocop:enable Metrics/AbcSize

def mock_s3(success: true)
  s3_client = S3Client.new
  s3_response = S3Response.new

  allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
  allow(s3_client).to receive(:put_object).and_return(s3_response)
  allow(s3_response).to receive(:successful?).and_return(success)
  s3_client
end

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

def mock_cognito(success: true)
  cognito_client = CognitoClient.new

  allow(Aws::CognitoIdentityProvider::Client).to receive(:new).and_return(cognito_client)
  allow(cognito_client).to receive(:describe_user_pool_client).and_return(CognitoResponse.new) if success
  allow(cognito_client).to receive(:describe_user_pool_client).and_raise(aws_error) unless success

  allow_any_instance_of(CognitoResponse).to receive(:user_pool_client).and_return(CognitoUserPool.new)

  cognito_client
end

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
def mock_dynamodb(item_array:, success: true)
  item_array = [] if item_array.nil?
  dynamodb_items = item_array.map { |item| DynamoItem.new(JSON.parse(item.to_json)) }
  dynamodb_response = DynamoResponse.new(dynamodb_items)
  # :get_item returns a Hash instead of a Response object
  dynamodb_hash = { item: JSON.parse(item_array.first.to_json) }

  # Stub out the responses from each client method
  dynamodb_client = DynamoClient.new(
    # update_item,     put_item,          get_item,                  query
    dynamodb_response, dynamodb_response, { item: item_array.first }, dynamodb_response
  )

  # Ensure that the SSM fetch of the TABLE_NAME is mocked
  mock_ssm(value: 'foo')

  allow(Aws::DynamoDB::Client).to receive(:new).and_return(dynamodb_client)
  # Stubbing count here instead of defining in the Struct because :count is
  # a Struct keyword
  allow(dynamodb_response).to receive(:count).and_return(item_array.length)
  allow(dynamodb_response).to receive(:successful?).and_return(success)

  # Mock a :get_item request which returns a single item
  allow(dynamodb_client).to receive(:get_item).and_return(dynamodb_hash) if success
  allow(dynamodb_client).to receive(:get_item).and_raise(aws_error) unless success

  # Mock a :put_item, :query, :scan and :update_item request which returns an array of items
  allow(dynamodb_client).to receive(:delete_item).and_return(dynamodb_response) if success
  allow(dynamodb_client).to receive(:put_item).and_return(dynamodb_response) if success
  allow(dynamodb_client).to receive(:query).and_return(dynamodb_response) if success
  allow(dynamodb_client).to receive(:scan).and_return(dynamodb_response) if success
  allow(dynamodb_client).to receive(:update_item).and_return(dynamodb_response) if success
  allow(dynamodb_client).to receive(:delete_item).and_raise(aws_error) unless success
  allow(dynamodb_client).to receive(:put_item).and_raise(aws_error) unless success
  allow(dynamodb_client).to receive(:query).and_raise(aws_error) unless success
  allow(dynamodb_client).to receive(:scan).and_raise(aws_error) unless success
  allow(dynamodb_client).to receive(:update_item).and_raise(aws_error) unless success
  dynamodb_client
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
# rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

# Mock a random DOI aka DMP ID
def mock_dmp_id(shoulder: mock_dmp_id_shoulder)
  id = "#{SecureRandom.hex(2)}.#{SecureRandom.hex(4)}/#{SecureRandom.hex(4)}"
  "#{mock_url.gsub('http://', '')}/#{shoulder}/#{id}"
end

# Mock DMP ID shoulder
def mock_dmp_id_shoulder
  "#{rand(0..99).to_s.rjust(2, '0')}.#{rand(0..9999).to_s.rjust(5, '0')}"
end

# Mock URL
def mock_url
  'http://example.com'
end

# Adds all of the specialized DMPHub attributes to the specified JSON to make
# it a valid DynamoDB item
def mock_dmp_item(json: nil, provenance: nil)
  file = File.read("#{Dir.pwd}/spec/support/json_mocks/minimal.json") if json.nil?
  json = JSON.parse(file)['author'] if json.nil?

  mock_provenance_item if provenance.nil?
  json
rescue JSON::ParserError
  nil
end

# Mocks a DMPHub Provenance DynamoDB item
def mock_provenance_item(name: nil, **args)
  name = 'Foo' if name.nil?
  item = {
    PK: "PROVENANCE##{name}",
    SK: 'PROFILE',
    seedingWithLiveDmpIds: false,
    contact: {
      email: 'admin@example.com',
      name: 'Provenance Administrator'
    },
    description: 'Mock DMPHub provenance',
    homepage: 'https://example.com',
    name: name,
    redirectUri: 'https://example.com/api/dmps/callback'
  }
  JSON.parse(item.merge(args).to_json)
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
def aws_sns_event(args: {})
  event = {
    Records: [{
      EventSource: 'aws:sns',
      EventVersion: '1.0',
      EventSubscriptionArn: 'arn:aws:sns:us-west-2:blah-blah-blah',
      Sns: {
        Type: 'Notification',
        MessageId: 'a7ba6aaf-0d52-5d94-968e-311e0661231f',
        TopicArn: 'arn:aws:sns:us-west-2:yadda-yadda-yadda',
        Subject: 'Test - register DMP ID',
        Message: {},
        Timestamp: '2022-09-30T15:19:15.182Z',
        SignatureVersion: '1',
        Signature: 'Jeh4PdtFzpNtnRpLrNYhO9C5JYfjGPiLQIoW+0RykbVroSIe==',
        SigningCertUrl: 'https://sns.us-west-2.amazonaws.com/SimpleNotificationService-foo.pem',
        UnsubscribeUrl: 'https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe',
        MessageAttributes: {}
      }
    }]
  }
  JSON.parse(event.merge(args).to_json)
end
# rubocop:enable Metrics/MethodLength

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
