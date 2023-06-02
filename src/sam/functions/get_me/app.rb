# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'

module Functions
  # The handler for POST /dmps/validate
  class GetMe
    SOURCE = 'GET /me'

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
    #    {
    #      "name": "Doe, Jane",
    #      "mbox": "jane.doe@example.com",
    #      "user_id": {
    #        "identifier": "https://orcid.org/0000-0000-0000-000X",
    #        "type": "orcid"
    #      },
    #      "affiliation": {
    #        "name": "California Digital Library (cdlib.org)",
    #        "affiliation_id": {
    #          "identifier": "https://ror.org/03yrm5c26",
    #          "type": "ror"
    #        }
    #      }
    #    }

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      def process(event:, context:)
        # Only process if there is a valid API token
        principal = event.fetch('requestContext', {}).fetch('authorizer', {})
        return _respond(status: 401, errors: [Uc3DmpRds::MSG_MISSING_USER], event: event) if principal.nil? ||
                                                                                             principal['mbox'].nil?

        # Debug, output the incoming Event and Context
        debug = Uc3DmpApiCore::SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        # Convert the user info into the standardized format to work with DMP JSON standards
        user = { name: principal['name'], mbox: principal['mbox'] }
        user['user_id'] = { type: 'orcid', identifier: principal['orcid'] } unless principal['orcid'].nil?
        user['affiliation'] = { name: principal['affiliation'] } unless principal['affiliation'].nil?
        id = { type: 'ror', identifier: principal['affiliation_id'] } unless principal['affiliation_id'].nil?
        user['affiliation']['affiliation_id'] = id unless id.nil?

        _respond(status: 200, items: [user], event: event)
      rescue Aws::Errors::ServiceError => e
        Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
      end

      private

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {})
        Uc3DmpApiCore::Responder.respond(status: status, items: items, errors: errors, event: event)
      end
    end
  end
end
