# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'

require 'dmp_finder'
require 'key_helper'
require 'messages'
require 'provenance_finder'
require 'responder'
require 'ssm_reader'

module Functions
  # The handler for: GET /dmps
  class GetDmps
    SOURCE = 'GET /dmps'

    # rubocop:disable Metrics/AbcSize
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

      params = event.fetch('queryStringParameters', {})
      page = params.fetch('page', Responder::DEFAULT_PAGE)
      page = Responder::DEFAULT_PAGE if page <= 1
      per_page = params.fetch('per_page', Responder::DEFAULT_PER_PAGE)
      per_page = Responder::DEFAULT_PER_PAGE if per_page >= Responder::MAXIMUM_PER_PAGE || per_page <= 1

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)

      # Get the DMP
      finder = DmpFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = finder.search_dmps(page: page, per_page: per_page)
      return Responder.respond(status: resp[:status], errors: resp[:error], event: event) unless resp[:status] == 200

      Responder.respond(status: 200, items: resp[:items], event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    end
    # rubocop:enable Metrics/AbcSize
  end
end
