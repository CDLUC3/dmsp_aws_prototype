# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'messages'
require 'responder'
require 'ssm_reader'
require 'validator'

module Functions
  # The handler for POST /dmps/validate
  class ValidateDmp
    SOURCE = 'POST /dmps/validate'

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

      body = event.fetch('body', '')

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp "EVENT: #{event}" if debug
      pp "CONTEXT: #{context}" if debug
      pp "BODY: #{body}" if debug
      # Debug, output the incoming Event and Context

      validation = Validator.validate(mode: 'author', json: body)
      return Responder.respond(status: 200, items: [Messages::MSG_VALID_JSON], event: event) if validation[:valid]

      Responder.respond(status: 400, errors: validation[:errors], event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    end
  end
end
