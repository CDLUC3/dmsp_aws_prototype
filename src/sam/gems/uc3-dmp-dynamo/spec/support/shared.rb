# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'json'
require 'ostruct'

# Mock AWS DynamoDB Table Resources
DynamoClient = Struct.new('DynamoClient', :update_item, :put_item, :get_item, :delete_item, :query, :scan)
# Dynamo returns an array in all cases but :get_item which returns a hash.
DynamoResponse = Struct.new('DynamoResponse', :items, :item, :successful?)
DynamoItem = Struct.new('DynamoItem', :item)

# Mock AWS Lambda Context
AwsContext = Struct.new(
  'AwsContext', :function_name, :function_version, :invoked_function_arn,
  :memory_limit_in_mb, :aws_request_id, :log_group_name, :log_stream_name,
  :deadline_ms, :identity, :client_context
)

def aws_error(msg: 'Testing')
  Aws::Errors::ServiceError.new(Seahorse::Client::RequestContext.new, msg)
end

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
def mock_dynamodb(item_array: [{}], success: true)
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
