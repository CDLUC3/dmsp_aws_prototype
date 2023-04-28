# frozen_string_literal: true

require 'active_record'
require 'active_record_simple_execute'
require 'aws-sdk-sns'
require 'aws-sdk-ssm'
require 'mysql2'

require 'uc3-dmp-api-core'

module Uc3DmpRds
  # An RDS Client to interact with the RDS DB. Expects the following ENV variables to be set:
  #     RDS_USERNAME:   The RDS username
  #     RDS_PASSWORD:   The RDS password
  #     DATABASE_HOST:  The host URL
  #     DATABASE_PORT:  The port to use
  #     DATABASE_NAME:  The name of the database
  #
  class Client
    class << self
      # Connect to the RDS instance
      def connect
        ActiveRecord::Base.establish_connection(
          adapter: 'mysql2',
          host: ENV["DATABASE_HOST"],
          port: ENV["DATABASE_PORT"],
          database: ENV["DATABASE_NAME"],
          username: ENV['RDS_USERNAME'],
          password: ENV['RDS_PASSWORD'],
          encoding: 'utf8mb4'
        )
      end

      def execute_query(sql:, **params)
        ActiveRecord::Base.simple_execute(sql, params)
      end
    end
  end
end
