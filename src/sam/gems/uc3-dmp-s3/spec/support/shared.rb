# frozen_string_literal: true

require 'ostruct'

# Mock S3 Resources
S3Client = Struct.new('S3Client', :put_object, :get_object)
S3PutResponse = Struct.new('S3PutResponse', :successful?)
S3GetResponse = Struct.new('S3GettResponse', :body, :content_length)
S3ResponseBody = Struct.new('S3ResponseBody', :read)

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

def mock_s3_writer(success: true)
  s3_client = S3Client.new
  s3_put_response = S3PutResponse.new

  allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
  allow(s3_client).to receive(:put_object).and_return(s3_put_response)
  allow(s3_put_response).to receive(:successful?).and_return(success)
  s3_client
end

# rubocop:disable Metrics/AbcSize
def mock_s3_reader(success: true, as_string: false)
  s3_client = S3Client.new
  s3_get_response = S3GetResponse.new
  body = as_string ? 'string body' : S3ResponseBody.new
  allow(body).to receive(:read).and_return('io body') unless as_string

  allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
  allow(s3_client).to receive(:get_object).and_return(s3_get_response)
  allow(s3_get_response).to receive(:body).and_return(success ? body : '')
  allow(s3_get_response).to receive(:content_length).and_return(success ? 8 : 0)
  s3_client
end
# rubocop:enable Metrics/AbcSize
