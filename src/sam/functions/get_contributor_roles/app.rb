# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-sns'
require 'aws-sdk-ssm'

require_relative 'lib/messages'
require_relative 'lib/responder'
require_relative 'lib/ssm_reader'

module Functions
  # The handler for POST /dmps/validate
  class GetContributorRoles
    SOURCE = 'GET /contributor_roles'.freeze

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
    #        "name": "Principal Investigator",
    #        "uri": "http://credit.niso.org/contributor-roles/investigation"
    #      },
    #      {
    #        "name": "Project Administrator",
    #        "uri": "http://credit.niso.org/contributor-roles/project_administration"
    #      }
    #    ]

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      def process(event:, context:)
        params = event.fetch('queryStringParameters', {})
        params = {} if params.nil?
        page = params.fetch('page', Responder::DEFAULT_PAGE)
        page = Responder::DEFAULT_PAGE if page <= 1
        per_page = params.fetch('per_page', Responder::DEFAULT_PER_PAGE)
        per_page = Responder::DEFAULT_PER_PAGE if per_page >= Responder::MAXIMUM_PER_PAGE || per_page <= 1

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        taxonomy_url = 'http://credit.niso.org/contributor-roles/'

        items = [
          {
            label: 'Data Curator',
            value: "#{taxonomy_url}data_curation"
          },
          {
            label: 'Principal Investigator',
            value: "#{taxonomy_url}investigation",
            default: "true"
          },
          {
            label: 'Project Administrator',
            value: "#{taxonomy_url}project_administration"
          },
          {
            label: 'Other',
            value: "#{taxonomy_url}other"
          }
        ]

        Responder.respond(status: 200, items: items, event: event, page: page, per_page: per_page)
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end
    end
  end
end
