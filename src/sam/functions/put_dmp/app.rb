# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'
require 'aws-sdk-sns'

require 'dmp_finder'
require 'dmp_helper'
require 'dmp_updater'
require 'key_helper'
require 'messages'
require 'provenance_finder'
require 'responder'
require 'ssm_reader'
require 'validator'

module Functions
  # The handler for PUT /dmps/{dmp_id+}
  class PutDmp
    SOURCE = 'PUT /dmps/{dmp_id+}'

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
      body = event.fetch('body', '')

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Fail if the DMP ID specified was not valid
      p_key = KeyHelper.path_parameter_to_pk(param: dmp_id)
      return Responder.respond(status: 400, errors: Messages::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      # Fail if the JSON is invalid
      validation = Validator.validate(mode: 'amend', json: body)
      return Responder.respond(status: 400, errors: validation[:errors], event: event) unless validation[:valid]

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)

      # Fail if the Provenance could not be loaded
      p_finder = ProvenanceFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = p_finder.provenance_from_lambda_cotext(identity: event.fetch('requestContext', {}))
      provenance = resp[:items].first if resp[:status] == 200

      # TODO: Remove this stub once Cognito is setup. We will need to see how the Cognito info is passed
      #       in and how we can fetch the provenance record.
      provenance = JSON.parse({ PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}dmptool" }.to_json) if provenance.nil?

      return Responder.respond(status: 403, errors: Messages::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Fail if the DMP ID specified could not be found
      finder = DmpFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = finder.find_dmp_by_pk(p_key: p_key)
      return Responder.respond(status: resp[:status], errors: resp[:error], event: event) unless resp[:status] == 200

      # Update the DMP
      updater = DmpUpdater.new(provenance: provenance, client: client, table_name: table, debug_mode: debug)
      resp = updater.update_dmp(p_key: p_key, json: body)
      Responder.respond(status: resp[:status], errors: resp[:error], items: resp[:items], event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end
