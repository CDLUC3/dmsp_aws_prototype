# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-rds'
require 'securerandom'

module Functions
  # The handler for saving Work in Progress (WIP) DMPs
  class PostWips
    SOURCE = 'POST /wips'

    MSG_INVALID_WIP = 'Unable to save the work in progress (WIP) record. Expected a JSON object like /
                       \'{ "dmp": { "title": "My example DMP", "dmphub_owner": { "mbox": "you@exmzple.com" } } }\''

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

    # Example body:
    #    [
    #      {
    #        "name": "California Digitial Library (cdlib.org)",
    #        "affiliation_id": {
    #          "identifier": "https://ror.org/03yrm5c26",
    #          "type": "ror"
    #        }
    #      },
    #      {
    #        "name": "University of Washington (washington.edu)",
    #        "funder_id": {
    #          "identifier": "https://ror.org/00cvxb145",
    #          "type": "ror"
    #        }
    #      }
    #    ]

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      # rubocop:disable Metrics/AbcSize
      def process(event:, context:)
        body = event.fetch('body', '{}').to_s.strip
        principal = event.fetch('requestContext', {}).fetch('authorizer', {})
        return _respond(status: 401, errors: [Uc3DmpRds::MSG_MISSING_USER], event: event) if principal.nil? ||
                                                                                             principal['mbox'].nil?

        continue = !body.empty?
        json = JSON.parse(body) if continue
        continue = !json.fetch('dmp', {})['title'].nil? if continue
        return _respond(status: 400, errors: [MSG_INVALID_WIP], event: event) unless continue

        # Debug, output the incoming Event and Context
        debug = Uc3DmpApiCore::SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        # Connect to the DB
        connected = _establish_connection
        return _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event) unless connected

        # Create the Work in Progress (WIP) record
        wip = _insert(owner: principal, wip: json)
        return _respond(status: 400, errors: [MSG_INVALID_WIP], event: event) if wip.nil?

        # Return the updated WIP record that now contains the :wip_id
        _respond(status: 201, items: [wip], event: event)
      rescue JSON::ParserError
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_INVALID_WIP], event: event)
      rescue Aws::Errors::ServiceError => e
        Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Run the search query against the DB and return the raw results
      def _insert(owner:, wip:)
        return nil if owner.nil? || owner['id'].nil?

        tstamp = Time.now.strftime('%Y-%m-%dT%H:%M:%S')
        id = "#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(6)}"
        wip['dmp']['dmphub_wip_id'] = { type: 'other', identifier: id }
        wip['dmp']['dmphub_owner_id'] = owner['id']

        sql_str = <<~SQL.squish
          INSERT INTO wips (identifier, metadata, created_at, updated_at)
          VALUES (:identifier, :metadata, :tstamp, :tstamp)
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, identifier: id, metadata: wip.to_json, tstamp: tstamp)
        wip
      end

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
