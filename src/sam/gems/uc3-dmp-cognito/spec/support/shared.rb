# frozen_string_literal: true

require 'aws-sdk-cognitoidentityprovider'
require 'json'
require 'ostruct'

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

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

# rubocop:disable Metrics/AbcSize
def mock_cognito(success: true, name: 'test')
  cognito_client = CognitoClient.new

  allow(Aws::CognitoIdentityProvider::Client).to receive(:new).and_return(cognito_client)
  allow(cognito_client).to receive(:describe_user_pool_client).and_return(CognitoResponse.new) if success
  allow(cognito_client).to receive(:describe_user_pool_client).and_raise(aws_error) unless success

  allow_any_instance_of(CognitoResponse).to receive(:user_pool_client).and_return(CognitoUserPool.new(name))

  cognito_client
end
# rubocop:enable Metrics/AbcSize
