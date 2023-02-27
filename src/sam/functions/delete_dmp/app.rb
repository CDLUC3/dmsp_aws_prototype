# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-cognitoidentityprovider'
require 'aws-sdk-dynamodb'
require 'aws-sdk-eventbridge'
require 'aws-sdk-sns'

require 'dmp_deleter'
require 'dmp_finder'
require 'dmp_helper'
require 'key_helper'
require 'messages'
require 'provenance_finder'
require 'responder'
require 'ssm_reader'

module Functions
  # The lambda handler for: DELETE /dmps/{dmp_id+}
  class DeleteDmp
    SOURCE = 'DELETE /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
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
      dmp_id = params['dmp_id']

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Fail if there was no DMP ID specified
      return Responder.respond(status: 404, errors: Messages::MSG_INVALID_JSON, event: event) if dmp_id.nil?

      # Fail if the DMP ID is not a valid DMP ID
      p_key = KeyHelper.path_parameter_to_pk(param: dmp_id)
      return Responder.respond(status: 400, errors: Messages::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)

      # Fail if the Provenance could not be loaded
      p_finder = ProvenanceFinder.new(client: client, table_name: table, debug_mode: debug)
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      resp = p_finder.provenance_from_lambda_cotext(identity: claim)
      provenance = resp[:items].first if resp[:status] == 200
      return Responder.respond(status: 403, errors: Messages::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Fail if the DMP ID could not be found
      finder = DmpFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = finder.find_dmp_by_pk(p_key: p_key)
      return Responder.respond(status: resp[:status], errors: resp[:error], event: event) unless resp[:status] == 200

      # Attempt to tombstone the DMP
      deleter = DmpDeleter.new(provenance: provenance, client: client, table_name: table, debug_mode: debug)
      resp = deleter.delete_dmp(p_key: p_key)
      Responder.respond(status: resp[:status], errors: resp[:error], items: resp[:items], event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
