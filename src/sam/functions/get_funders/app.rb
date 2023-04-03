# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'active_record'
require 'funder'
require 'messages'
require 'mysql2'
require 'responder'
require 'ssm_reader'

module Functions
  # The handler for POST /dmps/validate
  class GetFunders
    SOURCE = 'GET /funders?search=name'.freeze
    TABLE = 'registry_orgs'.freeze

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
    #        "name": "National Institutes of Health (nih.gov)",
    #        "funder_id": {
    #          "identifier": "https://api.crossref.org/funders/100000002",
    #          "type": "fundref"
    #        },
    #        "funder_api": "api.dmphub-dev.cdlib.org/funders/100000002/api",
    #        "funder_api_label": "Project lookup",
    #        "funder_api_guidance": "Please enter your research project title"
    #      },
    #      {
    #        "name": "National Science Foundation (nsf.gov)",
    #        "funder_id": {
    #          "identifier": "[https://api.crossref.org/funders/10000001](https://api.crossref.org/funders/100000001)",
    #          "type": "fundref"
    #        }
    #      }
    #    ]

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      def process(event:, context:)
        params = event.fetch('queryStringParameters', {})
        # Only process if there are 3 or more characters in the search
        continue = !params['search'].nil? || params['search'].length >= 3
        Responder.respond(status: 400, errors: [MSG_INVALID_ARGS], event: event) if continue

        page = params.fetch('page', Responder::DEFAULT_PAGE)
        page = Responder::DEFAULT_PAGE if page <= 1
        per_page = params.fetch('per_page', Responder::DEFAULT_PER_PAGE)
        per_page = Responder::DEFAULT_PER_PAGE if per_page >= Responder::MAXIMUM_PER_PAGE || per_page <= 1

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        items = Funder.search(params[:search]).map { |funder| funder.to_json }
        Responder.respond(status: 200, items: [items], event: event)
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end

      private

      def db_client
        ActiveRecord::Base.establish_connection(
          adapter: 'mysql2',
          host: ENV["RDS_HOST"],
          username: SsmReader.get_ssm_value(key: SsmReader::RDS_USERNAME),
          password: SsmReader.get_ssm_value(key: SsmReader::RDS_PASSWORD),
          database: ENV["RDS_DB_NAME"],
          port: ENV["RDS_PORT"]
        )
      end
    end
  end
end
