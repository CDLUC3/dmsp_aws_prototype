# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'responder'

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
        item = {
          name: "Doe PhD., Jane A.",
          mbox: "jane.doe@example.com",
          user_id: {
            identifier: "https://orcid.org/0000-0000-0000-000X",
            type: "orcid"
          },
          affiliation: {
            name: "California Digital Library (cdlib.org)",
            affiliation_id: {
              identifier: "https://ror.org/03yrm5c26",
              type: "ror"
            }
          }
        }
        Responder.respond(status: 200, items: [item.to_json], event: event)
      end
    end
  end
end
