# frozen_string_literal: true

require 'active_record'
require 'active_record_simple_execute'
require 'aws-sdk-sns'
require 'aws-sdk-ssm'
require 'mysql2'

require 'uc3-dmp-api-core'

module Uc3DmpRds
  # A module to interact with the RDS DB. Expects the following ENV variables to be set:
  #     DATABASE_HOST:  The host URL
  #     DATABASE_PORT:  The port to use
  #     DATABASE_NAME:  The name of the database
  #
  # and the following from the AWS SSM parameter store:
  #     RDS_USERNAME:   The RDS username
  #     RDS_PASSWORD:   The RDS password
  #
  class Adapter
    MSG_NO_CONNECTION = 'No current database connection. Call Uc3DmpRds.connect first.'
    MSG_KEYWORDS_INVALID = 'The parameters specified do not match those in the SQL query.'

    class << self
      # Connect to the RDS instance
      def connect
        creds = _credentials
        ActiveRecord::Base.establish_connection(
          adapter: 'mysql2',
          host: ENV.fetch('DATABASE_HOST', nil),
          port: ENV.fetch('DATABASE_PORT', nil),
          database: ENV.fetch('DATABASE_NAME', nil),
          username: creds[:username],
          password: creds[:password],
          encoding: 'utf8mb4'
        )
        ActiveRecord::Base.connected?
      end

      # Execute the specified query using ActiveRecord's helpers to sanitize the input
      def execute_query(sql:, **params)
        raise StandardError, MSG_NO_CONNECTION unless ActiveRecord::Base.connected?
        return [] unless sql.is_a?(String) && !sql.strip.empty? && (params.nil? || params.is_a?(Hash))
        # Verify that all of the kewords are accounted for and that values were supplied
        raise StandardError, MSG_KEYWORDS_INVALID unless _verify_params(sql: sql, params: params)

        ActiveRecord::Base.simple_execute(sql, params)
      end

      private

      # Fetch the DB credentials from SSM parameter store
      def _credentials
        {
          username: Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_username),
          password: Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_password)
        }
      end

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
