# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-rds'

module Functions
  # The handler for: DELETE /dmps/{dmp_id+}
  class DeleteWip
    SOURCE = 'DELETE /wips/{wip_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.process(event:, context:)
      # Sample pure Lambda function

      # Parameters
      # ----------
      # event: Hash, required
      #     API Gateway Lambda Proxy Input Format
      #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

      # context: object, required
      #     Lambda Context runtime methods and attributes
      #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

      # Returns
      # ------
      # API Gateway Lambda Proxy Output Format: dict
      #     'statusCode' and 'body' are required
      #     # api-gateway-simple-proxy-for-lambda-output-format
      #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html

      # begin
      #   response = HTTParty.get('http://checkip.amazonaws.com/')
      # rescue HTTParty::Error => error
      #   puts error.inspect
      #   raise error
      # end
      params = event.fetch('pathParameters', {})
      wip_id = params['wip_id']
      return _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS], event: event) if wip_id.nil?

      principal = event.fetch('requestContext', {}).fetch('authorizer', {})
      continue = !principal.nil? && !principal['id'].nil?
      return _respond(status: 403, errors: [Uc3DmpApiCore::MSG_FORBIDDEN], event: event) unless continue

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Connect to the DB
      connected = _establish_connection
      return _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event) unless connected

      # Get the WIP and verify that the user has authority to delete it
      wips = _get(wip_id: wip_id)
      continue = wips.is_a?(Array) && !wips.empty?
      original = JSON.parse(wips.first['metadata'])
      owner_id = original.fetch('dmp', {})['dmphub_owner_id'] if continue

puts wips
puts "CURRENT_USER: #{principal['id']}"
puts "OWNER OF RECORD: #{owner_id}"

      continue = owner_id.to_s.strip == principal['id'].to_s.strip if continue
      return _respond(status: 403, errors: [Uc3DmpApiCore::MSG_FORBIDDEN], event: event) unless continue

      # Delete the record
      _delete(wip_id: wip_id)
      _respond(status: 200, items: [], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    class << self
      def _get(wip_id:)
        sql_str = <<~SQL.squish
          SELECT * FROM wips WHERE identifier = :wip_id
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, wip_id: wip_id)
      end

      # Run the search query against the DB and return the raw results
      def _delete(wip_id:)
        sql_str = <<~SQL.squish
          DELETE FROM wips WHERE identifier = :wip_id
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, wip_id: wip_id)
      end

      # make a connection to the RDS DB
      def _establish_connection
        # Fetch the DB credentials from SSM parameter store
        username = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_username)
        password = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_password)
        Uc3DmpRds::Adapter.connect(username: username, password: password)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {})
        Uc3DmpApiCore::Responder.respond(status: status, items: items, errors: errors, event: event)
      end
    end
  end
end
