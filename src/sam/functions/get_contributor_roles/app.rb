# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'

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
        # Only process if there is a valid API token
        principal = event.fetch('requestContext', {}).fetch('authorizer', {})
        return _respond(status: 401, errors: [Uc3DmpApiCore::MSG_FORBIDDEN], event: event) if principal.nil? ||
                                                                                              principal['mbox'].nil?

        # Debug, output the incoming Event and Context
        debug = Uc3DmpApiCore::SsmReader.debug_mode?
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

        _respond(status: 200, items: [items], event: event, params: params)
      rescue Aws::Errors::ServiceError => e
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
      end

      private

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(status: status, items: items, errors: errors, event: event)
      end
    end
  end
end
