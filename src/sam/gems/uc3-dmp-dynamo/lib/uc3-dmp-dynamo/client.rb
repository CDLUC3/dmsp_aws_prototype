# frozen_string_literal: true

module Uc3DmpDynamo
  class ClientError < StandardError; end

  # Helper functions for working with Dynamo JSON
  class Client
    SOURCE = 'Uc3DmpDynamo::Client'

    MSG_INVALID_KEY = 'Invalid key specified. Expecting Hash containing `PK` and `SK`'
    MSG_MISSING_TABLE = 'No Dynamo Table defined! Looking for `ENV[\'DYNAMO_TABLE\']`'
    MSG_DYNAMO_ERROR = 'Dynamo DB Table Error - %{msg} - %{trace}'

    attr_accessor :connection, :table

    def initialize(**_args)
      @table = ENV.fetch('DYNAMO_TABLE', nil)
      raise ClientError, MSG_MISSING_TABLE if @table.nil?

      @connection = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
    end

    # Fetch a single item
    # rubocop:disable Metrics/AbcSize
    def get_item(key:, debug: false)
      raise ClientError, MSG_INVALID_KEY unless key.is_a?(Hash) && !key[:PK].nil?

      resp = @connection.get_item(
        { table_name: @table,
          key: key,
          consistent_read: false,
          return_consumed_capacity: debug ? 'TOTAL' : 'NONE' }
      )

      # If debug is enabled then write the response to the LogWriter
      if debug
        puts "#{SOURCE} => get_item - #{key}"
        puts resp[:item].first.inspect
      end
      resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end
    # rubocop:enable Metrics/AbcSize

    # Perform a table scan if a filter was specified.
    # For example:
    #    key_conditions: { PK: { attribute_value_list: ['DMP#12345'] }, comparison_operator: 'EQ' }
    #    projection_expression: 'title, dmp_id, modified'
    #
    # See the DynamoDB docs for examples of key_conditions and projection_expressions
    # rubocop:disable Metrics/AbcSize
    def query(args:, debug: false)
      raise ClientError, MSG_INVALID_KEY unless args.is_a?(Hash) && args.fetch(:key_conditions, {}).any?

      hash = {
        table_name: @table,
        key_conditions: args[:key_conditions],
        consistent_read: false,
        return_consumed_capacity: debug ? 'TOTAL' : 'NONE'
      }
      # Look for and add any other filtering or projection args
      %i[filter_expression expression_attribute_values projection_expression scan_index_forward].each do |key|
        next if args[key.to_sym].nil?

        hash[key.to_sym] = args[key.to_sym]
      end

      resp = @connection.query(hash)
      # If debug is enabled then write the response to the LogWriter
      if debug
        puts "#{SOURCE} => query - args: #{hash.inspect}"
        puts resp.items.inspect
      end
      return [] unless resp.items.any?
      return resp.items if resp.items.first.is_a?(Hash)

      resp.items.first.respond_to?(:item) ? resp.items.map(&:item) : resp.items
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end
    # rubocop:enable Metrics/AbcSize

    # Create/Update an item
    def put_item(json:, debug: false)
      json = Helper.parse_json(json: json)
      raise ClientError, MSG_INVALID_KEY unless json.is_a?(Hash) && !json['PK'].nil? && !json['SK'].nil?

      resp = @connection.put_item(
        { table_name: @table,
          item: json,
          consistent_read: false,
          return_consumed_capacity: debug ? 'TOTAL' : 'NONE'
        }
      )

      # If debug is enabled then write the response to the LogWriter
      if debug
        puts "#{SOURCE} => put_item -"
        puts json
        puts resp.inspect
      end
      resp
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end

    # Delete an item
    def delete_item(p_key:, s_key:, debug: false)
      json = Helper.parse_json(json: json)
      raise ClientError, MSG_INVALID_KEY unless json.is_a?(Hash) && !json['PK'].nil? && !json['SK'].nil?

      resp = @connection.delete_item(
        {
          table_name: @table,
          key: {
            PK: p_key,
            SK: s_key
          }
        }
      )
      # If debug is enabled then write the response to the LogWriter
      if debug
        puts "#{SOURCE} => delete_item -"
        puts json
        puts resp.inspect
      end
      resp
    end
  end
end
