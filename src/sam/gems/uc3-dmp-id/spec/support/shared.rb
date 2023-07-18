# frozen_string_literal: true

require 'ostruct'

require 'ostruct'

# Mock S3 Resources
Uc3DmpDynamoClient = Struct.new('S3Client', :get_item, :put_item, :delete_item, :query)

def mock_uc3_dmp_dynamo(success: true)
  client = Uc3DmpDynamoClient.new
  allow(client).to receive(:get_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:put_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:delete_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:query).and_return(success ? [mock_dmp] : nil)

  allow(Uc3DmpDynamo::Client).to receive(:new).and_return(client)
end

def mock_dmp
  JSON.parse({
    dmp: {

    }
  }.to_json)
end