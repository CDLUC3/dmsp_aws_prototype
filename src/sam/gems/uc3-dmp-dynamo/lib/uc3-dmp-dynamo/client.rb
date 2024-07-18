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

    def initialize(**args)
      @table = args.fetch(:table, ENV.fetch('DYNAMO_TABLE', nil))
      raise ClientError, MSG_MISSING_TABLE if @table.nil?

      @connection = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
    end

    # Quick get_item that only returns the PK to validate that the item exists
    def pk_exists?(key:, logger: nil)
      return nil unless key.is_a?(Hash) && !key['PK'].nil?

      resp = client.get_item(table_name: @table, key:, projection_expression: 'PK', logger:)
      resp.item.is_a?(Hash) && resp.item['PK'] == key['PK']
    end

    # Fetch a single item
    # rubocop:disable Metrics/AbcSize
    def get_item(key:, logger: nil)
      raise ClientError, MSG_INVALID_KEY unless key.is_a?(Hash) && !key[:PK].nil?

      resp = @connection.get_item(
        { table_name: @table,
          key:,
          consistent_read: false,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE' }
      )

      logger.debug(message: "#{SOURCE} fetched DMP ID: #{key}") if logger.respond_to?(:debug)
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
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def query(args:, logger: nil)
      raise ClientError, MSG_INVALID_KEY unless args.is_a?(Hash) &&
                                                (args.fetch(:key_conditions, {}).any? ||
                                                 args.fetch(:key_condition_expression, {}).any?)

      hash = {
        table_name: @table,
        consistent_read: false,
        return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
      }
      if args.fetch(:key_condition_expression, {}).any?
        hash[:key_condition_expression] = args[:key_condition_expression]
      else
        hash[:key_conditions] = args[:key_conditions]
      end

      # Look for and add any other filtering or projection args
      %i[index_name filter_expression expression_attribute_values projection_expression
         scan_index_forward].each do |key|
        next if args[key.to_sym].nil?

        hash[key.to_sym] = args[key.to_sym]
      end

      logger.debug(message: "#{SOURCE} queried for: #{hash}") if logger.respond_to?(:debug)
      resp = @connection.query(hash)
      return [] unless resp.items.any?
      return resp.items if resp.items.first.is_a?(Hash)

      resp.items.first.respond_to?(:item) ? resp.items.map(&:item) : resp.items
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def scan(args:, logger: nil)
      hash = {
        table_name: @table,
        consistent_read: false,
        return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
      }
      # Look for and add any other filtering or projection args
      %i[filter_expression expression_attribute_values projection_expression expression_attribute_names].each do |key|
        next if args[key.to_sym].nil?

        hash[key.to_sym] = args[key.to_sym]
      end

      logger.debug(message: "#{SOURCE} queried for: #{hash}") if logger.respond_to?(:debug)
      resp = @connection.scan(hash)
      return [] unless resp.items.any?
      return resp.items if resp.items.first.is_a?(Hash)

      resp.items.first.respond_to?(:item) ? resp.items.map(&:item) : resp.items
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Create/Update an item
    # rubocop:disable Metrics/AbcSize
    def put_item(json:, logger: nil)
      raise ClientError, MSG_INVALID_KEY unless json.is_a?(Hash) && !json['PK'].nil? && !json['SK'].nil?

      resp = @connection.put_item(
        {
          table_name: @table,
          item: json,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        }
      )

      logger.debug(message: "#{SOURCE} put_item DMP ID: #{json['PK']}", details: json) if logger.respond_to?(:debug)
      resp
    rescue Aws::Errors::ServiceError => e
      raise ClientError, format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace)
    end
    # rubocop:enable Metrics/AbcSize

    # Delete an item
    def delete_item(p_key:, s_key:, logger: nil)
      raise ClientError, MSG_INVALID_KEY if p_key.nil? || s_key.nil?

      resp = @connection.delete_item(
        {
          table_name: @table,
          key: {
            PK: p_key,
            SK: s_key
          }
        }
      )
      logger.debug(message: "#{SOURCE} deleted PK: #{p_key}, SK: #{s_key}") if logger.respond_to?(:debug)
      resp
    end
  end
end
