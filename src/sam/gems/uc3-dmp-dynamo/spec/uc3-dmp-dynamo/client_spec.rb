# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpDynamo::Client' do
  let!(:described_class) { Uc3DmpDynamo::Client }
  let!(:client_err) { Uc3DmpDynamo::ClientError }

  describe 'intialize(**args)' do
    it 'raises an error if the default table name is not set in the ENV' do
      ENV.delete('DYNAMO_TABLE')
      expect { described_class.new }.to raise_error(client_err, described_class::MSG_MISSING_TABLE)
    end

    it 'establishes a connection to the DynamoDB table' do
      mock_dynamodb
      ENV['DYNAMO_TABLE'] = 'foo'
      client = described_class.new
      expect(client.connection.class).to be(Struct::DynamoClient)
      expect(client.table).to eql('foo')
    end
  end

  describe 'get_item(key:, debug:)' do
    let!(:key) { { PK: 'DMP#foo', SK: 'VERSION#bar' } }

    it 'raises an error if :key is not a Hash' do
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expect { client.get_item(key: nil) }.to raise_error(client_err, described_class::MSG_INVALID_KEY)
    end

    it 'raises an error if :key does not contain :PK' do
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      key = { SK: 'VERSION#foo' }
      expect { client.get_item(key:) }.to raise_error(client_err, described_class::MSG_INVALID_KEY)
    end

    it 'returns an empty item if DynamoDB returned no items' do
      mock_dynamodb(item_array: [])
      client = Uc3DmpDynamo::Client.new
      expect(client.get_item(key:)).to be_nil
    end

    it 'returns the expected item' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      expect(client.get_item(key:)).to eql(JSON.parse({ foo: 'bar' }.to_json))
    end

    it 'does not log response item if :debug is false' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      allow(client).to receive(:puts).and_return(true)
      expected = { table_name: 'foo', key:, consistent_read: false, return_consumed_capacity: 'NONE' }

      expect(client.get_item(key:)).to eql(JSON.parse({ foo: 'bar' }.to_json))
      expect(client.connection).to have_received(:get_item).with(expected)
      expect(client).not_to have_received(:puts)
    end

    it 'logs response item if :debug is true' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      allow(client).to receive(:puts).and_return(true)
      expected = { table_name: 'foo', key:, consistent_read: false, return_consumed_capacity: 'TOTAL' }

      expect(client.get_item(key:, debug: true)).to eql(JSON.parse({ foo: 'bar' }.to_json))
      expect(client.connection).to have_received(:get_item).with(expected)
      expect(client).to have_received(:puts).twice
    end

    it 'handles Aws::Errors::ServiceError properly' do
      mock_dynamodb(success: false)
      client = Uc3DmpDynamo::Client.new
      expect { client.get_item(key:) }.to raise_error(client_err)
    end
  end

  describe 'query(args:, debug:)' do
    let!(:args) { { key_conditions: { foo: 'bar' } } }

    it 'raises an error if :args is not a Hash' do
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expect { client.query(args: nil) }.to raise_error(client_err, described_class::MSG_INVALID_KEY)
    end

    it 'raises an error if :args has no :key_conditions defined' do
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expect { client.query(args: { foo: 'bar' }) }.to raise_error(client_err, described_class::MSG_INVALID_KEY)
    end

    it 'uses the specified :filter_expression' do
      args[:filter_expression] = { hello: 'world' }
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   filter_expression: { hello: 'world' }, return_consumed_capacity: 'NONE' }

      client.query(args:)
      expect(client.connection).to have_received(:query).with(expected)
    end

    it 'uses the specified :expression_attribute_values' do
      args[:expression_attribute_values] = { hello: 'world' }
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   expression_attribute_values: { hello: 'world' }, return_consumed_capacity: 'NONE' }

      client.query(args:)
      expect(client.connection).to have_received(:query).with(expected)
    end

    it 'uses the specified :projection_expression' do
      args[:projection_expression] = { hello: 'world' }
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   projection_expression: { hello: 'world' }, return_consumed_capacity: 'NONE' }

      client.query(args:)
      expect(client.connection).to have_received(:query).with(expected)
    end

    it 'uses the specified :scan_index_forward' do
      args[:scan_index_forward] = { hello: 'world' }
      mock_dynamodb
      client = Uc3DmpDynamo::Client.new
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   scan_index_forward: { hello: 'world' }, return_consumed_capacity: 'NONE' }

      client.query(args:)
      expect(client.connection).to have_received(:query).with(expected)
    end

    it 'returns an empty array if DynamoDB returned no items' do
      mock_dynamodb(item_array: [])
      client = Uc3DmpDynamo::Client.new
      expect(client.query(args:)).to eql([])
    end

    it 'returns the expected items' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      expect(client.query(args:).first).to eql(JSON.parse({ foo: 'bar' }.to_json))
    end

    it 'does not log response items if :debug is false' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      allow(client).to receive(:puts).and_return(true)
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   return_consumed_capacity: 'NONE' }

      expect(client.query(args:).first).to eql(JSON.parse({ foo: 'bar' }.to_json))
      expect(client.connection).to have_received(:query).with(expected)
      expect(client).not_to have_received(:puts)
    end

    it 'logs response items if :debug is true' do
      mock_dynamodb(item_array: [JSON.parse({ foo: 'bar' }.to_json)])
      client = Uc3DmpDynamo::Client.new
      allow(client).to receive(:puts).and_return(true)
      expected = { table_name: 'foo', key_conditions: { foo: 'bar' }, consistent_read: false,
                   return_consumed_capacity: 'TOTAL' }

      expect(client.query(args:, debug: true).first).to eql(JSON.parse({ foo: 'bar' }.to_json))
      expect(client.connection).to have_received(:query).with(expected)
      expect(client).to have_received(:puts).twice
    end

    it 'handles Aws::Errors::ServiceError properly' do
      mock_dynamodb(success: false)
      client = Uc3DmpDynamo::Client.new
      expect { client.query(args:) }.to raise_error(client_err)
    end
  end
end
