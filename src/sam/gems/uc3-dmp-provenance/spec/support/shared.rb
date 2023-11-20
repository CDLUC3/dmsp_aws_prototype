# frozen_string_literal: true

require 'aws-sdk-cognitoidentityprovider'
require 'json'
require 'ostruct'

# Mock a random DOI aka DMP ID
def mock_dmp_id(shoulder: mock_dmp_id_shoulder)
  id = "#{SecureRandom.hex(2)}.#{SecureRandom.hex(4)}/#{SecureRandom.hex(4)}"
  "#{mock_url.gsub('http://', '')}/#{shoulder}/#{id}"
end

# Mock DMP ID shoulder
def mock_dmp_id_shoulder
  "#{rand(0..99).to_s.rjust(2, '0')}.#{rand(0..9999).to_s.rjust(5, '0')}"
end

def mock_url
  'http://example.com/api'
end

# Mock AWS Lambda Context
AwsContext = Struct.new(
  'AwsContext', :function_name, :function_version, :invoked_function_arn,
  :memory_limit_in_mb, :aws_request_id, :log_group_name, :log_stream_name,
  :deadline_ms, :identity, :client_context
)

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end
