# frozen_string_literal: true

require 'ostruct'

Uc3DmpDynamoClient = Struct.new('Uc3DmpDynamoClient', :get_item)

def mock_uc3_dmp_dynamo(success: true)
  client = DynamoClient.new()
  allow(client).to receive(:get_item).and_return(json) if success
  allow(client).to receive(:get_item).and_return(nil) unless success

  allow(Uc3DmpDynamo::Client).to receive(:new).and_return(client))
end
