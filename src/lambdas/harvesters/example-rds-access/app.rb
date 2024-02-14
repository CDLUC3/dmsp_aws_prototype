# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'active_record'
require 'active_record_simple_execute'
require 'digest'
require 'trilogy'
require 'uri'
require 'zip'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-external-api'

module Functions
  # An example function that builds as an ECR image and has access to an RDS database
  class ExampleRdsAccess
    NO_HARVESTER_RECORD_MSG = 'No record found for `example` in the RDS database\'s `external_sources` table'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "ExploreRdsAccess",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {}
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        # No need to validate the source and detail-type because that is done by the EventRule
        details = event.fetch('detail', {})
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : nil
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # Connect to MySQL
        establish_connection(logger:)

        # Fetch the ROR Source record from MySQL (or create it if this is the first time!)
        source = find_or_create_source(logger:)
        logger&.debug(message: 'Fetched harvester record from RDS.', details: source)
        logger&.error(message: NO_HARVESTER_RECORD_MSG) if source.nil?
        return { statusCode: 500, body: NO_HARVESTER_RECORD_MSG } if source.nil?

        # Finally update the harvester record in RDS
        update_harvester_record(id: source[:id], metadata: '', tstamp: Time.now.utc.iso8601, logger:)
        return { statusCode: 200, body: 'Success' }
      rescue StandardError => e
        puts "Fatal error in ExampleRdsAccess! #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: "Fatal Server Error" }
      end

      private

      # Fetch the latest RDS Database info from SecretsManager
      def fetch_db_info
        hash = {}
        secret_name = "dmp-hub-#{ENV.fetch('LAMBDA_ENV', 'dev')}-rails-app"
        client = Aws::SecretsManager::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        if get_secret_value_response.secret_string
          secret_json = get_secret_value_response.secret_string
          secret_hash = JSON.parse(secret_json)
          hash[:host] = secret_hash['host']
          hash[:port] = secret_hash['port']
          hash[:username] = secret_hash['username']
          hash[:password] = secret_hash['password']
          hash[:name] = secret_hash['dbname']
        end
        hash
      end

      # Establish a connection to the RDS instance
      def establish_connection
        hash = fetch_db_info
        ActiveRecord::Base.establish_connection(adapter: 'trilogy', encoding: 'utf8mb4',
                                                host: hash[:host], port: hash[:port], database: hash[:name],
                                                username: hash[:username], password: hash[:password])
      rescue StandardError => e
        logger&.error(message: "ERROR when trying to connect to RDS: #{e.message}", details: e.backtrace)
        nil
      end

      # Fetch the ROR Harvester record from the RDS instance or create it
      def find_or_create_source(logger:)
        record = fetch_harvester_record(logger:)
        return record unless record.nil?

        # If it was not found, create the record and then return the new record
        create_sql = <<~SQL.squish
          INSERT INTO external_sources (name, extraction_type, created_at, updated_at)
          VALUES (:name, :extraction_type, :tstamp, :tstamp)
        SQL
        ActiveRecord::Base.simple_execute(create_sql, name: 'ror', extraction_type: 'download', tstamp: Time.now.utc)
        fetch_harvester_record(logger:)
      rescue StandardError => e
        logger&.error(message: "ERROR when trying to create a Example harvester record in RDS: #{e.message}", details: e.backtrace)
        nil
      end

      # Find the harvester's record in the RDS database
      def fetch_harvester_record(logger:)
        select_sql = 'SELECT id, name, last_metadata_fetched, last_fetch_at FROM external_sources WHERE name = :name'
        record = ActiveRecord::Base.simple_execute(select_sql, name: 'ror')&.first
        return nil if record.nil? || record.length <= 0 || record[1]&.downcase != 'example'

        { id: record[0], name: record[1], last_metadata: record[2], last_fetched: record[3] }
      rescue StandardError => e
        logger&.error(message: "ERROR when trying to find the Example harvester record in RDS: #{e.message}", details: e.backtrace)
        nil
      end

      # Update the harvester's record in the RDS database
      def update_harvester_record(id:, metadata:, tstamp:, logger:)
        update_sql = 'UPDATE external_sources SET last_metadata_fetched = :metadata, last_fetch_at = :tstamp WHERE id = :id'
        ActiveRecord::Base.simple_execute(update_sql, id:, metadata: metadata.to_json, tstamp:)
        true
      rescue StandardError => e
        logger&.error(message: "ERROR when updating the Example harvester record in RDS: #{e.message}", details: e.backtrace)
        false
      end
    end
  end
end
