# frozen_string_literal: true

require 'active_record'
require 'active_record_simple_execute'
require 'trilogy'

module Uc3DmpRds
  # Error from the Rds Adapter
  class AdapterError < StandardError; end

  # A module to interact with the RDS DB. Expects the following ENV variables to be set:
  #     DATABASE_HOST:  The host URL
  #     DATABASE_PORT:  The port to use
  #     DATABASE_NAME:  The name of the database
  #
  # and the following should be passed into the :connect method:
  #     RDS_USERNAME:   The RDS username
  #     RDS_PASSWORD:   The RDS password
  #
  class Adapter
    MSG_KEYWORDS_INVALID = 'The parameters specified do not match those in the SQL query'
    MSG_MISSING_CREDENTIALS = 'No username and/or password specified'
    MSG_UNABLE_TO_CONNECT = 'Unable to establish a connection'
    MSG_UNABLE_TO_QUERY = 'Unable to process the query'
    MSG_UNAUTHORIZED = 'You are not authorized to perform that action'

    class << self
      # Connect to the RDS instance
      # rubocop:disable Metrics/AbcSize
      def connect(username:, password:)
        raise AdapterError, MSG_MISSING_CREDENTIALS if username.nil? || username.to_s.strip.empty? ||
                                                       password.nil? || password.to_s.strip.empty?

        connection = ActiveRecord::Base.establish_connection(
          adapter: 'trilogy',
          host: ENV.fetch('DATABASE_HOST', nil),
          port: ENV.fetch('DATABASE_PORT', nil),
          database: ENV.fetch('DATABASE_NAME', nil),
          username:,
          password:,
          encoding: 'utf8mb4'
        )
        !connection.nil?
      rescue StandardError => e
        raise AdapterError, "#{MSG_UNABLE_TO_CONNECT} - #{e.message}"
      end
      # rubocop:enable Metrics/AbcSize

      # Execute the specified query using ActiveRecord's helpers to sanitize the input
      def execute_query(sql:, **params)
        return [] unless sql.is_a?(String) && !sql.strip.empty? && (params.nil? || params.is_a?(Hash))
        # Verify that all of the kewords are accounted for and that values were supplied
        raise AdapterError, MSG_KEYWORDS_INVALID unless _verify_params(sql:, params:)

        ActiveRecord::Base.simple_execute(sql, params)
      rescue StandardError => e
        raise AdapterError, "#{MSG_UNABLE_TO_QUERY} - #{e.message}"
      end

      private

      # Verify that all params defined in the SQL exist in the params hash and vice versa
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def _verify_params(sql:, params:)
        # If the :sql doesn't have any parms and there are no :params then return true
        return true if !sql.to_s.include?(':') && !params.is_a?(Hash)
        # If the :sql has params but there are no :params return false
        return false if sql.to_s.include?(':') && !params.is_a?(Hash)
        # If the :sql has no params but there are :params return false
        return false if params.is_a?(Hash) && !sql.include?(':')

        resolvable = true
        keywords = sql.scan(/:[a-zA-Z_]+/)

        params&.keys&.each { |key| resolvable = false unless sql.include?(":#{key}") }
        keywords.each { |key| resolvable = false unless params.keys.map(&:to_s).include?(key.sub(':', '')) }
        resolvable
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
