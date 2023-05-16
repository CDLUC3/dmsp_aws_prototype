# frozen_string_literal: true


# TODO: Be sure to update the API functions so that they call cleanse_dmp_json before
#       calling Uc3DmpApiCore::Responder.respond !!!!!!!!!!


module Uc3DmpDynamo
  class Uc3DmpDynamoError < StandardError; end

  # Helper functions for working with Dynamo JSON
  class Client
    SOURCE = 'Uc3DmpDynamo::Client'

    MSG_INVALID_KEY = 'Invalid key specified. Expecting Hash containing `PK` and `SK`'
    MSG_MISSING_TABLE = 'No Dynamo Table defined! Looking for `ENV[\'DYNAMO_TABLE\']`'
    MSG_DYNAMO_ERROR = 'Dynamo DB Table Error - %{msg} - %{trace}'

    attr_accessor :connection, :table

    def initialize(**args)
      @table = ENV['DYNAMO_TABLE']
      raise Uc3DmpDynamoError, MSG_MISSING_TABLE if @table.nil?

      @connection = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
    end

    # Fetch a single item
    def get_item(key:, debug: false)
      raise Uc3DmpDynamoError, MSG_INVALID_KEY unless key.is_a?(Hash)

      resp = @connection.get_item(
        { table_name: @table,
          key: key,
          consistent_read: false,
          return_consumed_capacity: debug ? 'TOTAL' : 'NONE'
        }
      )
      # If debug is enabled then write the response to the LogWriter
      if debug
        puts "#{SOURCE} => get_item - #{key}"
        puts resp[:item].first.inspect
      end
      resp[:item].first
    rescue Aws::Errors::ServiceError => e
      raise Uc3DmpDynamoError, MSG_DYNAMO_ERROR % { msg: e.message, trace: e.backtrace }
    end

    # Perform a table scan if a filter was specified.
    # For example:
    #    key_conditions: { PK: { attribute_value_list: ['DMP#12345'] }, comparison_operator: 'EQ' }
    #    projection_expression: 'title, dmp_id, modified'
    #
    # See the DynamoDB docs for examples of key_conditions and projection_expressions
    def query(debug: false, **args)
      raise Uc3DmpDynamoError, MSG_INVALID_KEY unless args[:key_conditions].is_a?(Hash) &&
                                                      !args[:key_conditions].keys.empty?

      hash = {
        table_name: @table,
        key_conditions: args[:key_conditions],
        consistent_read: false,
        return_consumed_capacity: debug ? 'TOTAL' : 'NONE'
      }
      # Look for and add any other filtering or projection args
      %i[filter_expression, expression_attribute_values, projection_expression, scan_index_forward].each do |key|
        next if args[key.to_sym].nil?

        hash[key.to_sym] = args[key.to_sym]
      end

      resp = @connection.query(hash)
      # If debug is enabled then write the response to the LogWriter
      if debug
        msg = "query - args: #{args}"
        puts "#{SOURCE} => query - args: #{args.inspect}"
        puts resp.items.inspect
      end
      resp.items
    rescue Aws::Errors::ServiceError => e
      raise Uc3DmpDynamoError, MSG_DYNAMO_ERROR % { msg: e.message, trace: e.backtrace }
    end
  end
end