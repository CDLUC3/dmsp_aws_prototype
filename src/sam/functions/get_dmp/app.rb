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
  # The handler for: GET /dmps/{dmp_id+}
  class GetDmp
    SOURCE = 'GET /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
      version = params['version']

      # Rails' ActiveResource won't pass query strings, so see if its part of the path
      ver_param = '%3Fversion%3D'
      version = dmp_id.split(ver_param).last if version.nil? && dmp_id&.include?(ver_param)
      version = CGI.unescape(version).gsub(' ', '+') unless version.nil?

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Fail if there was no DMP ID specified
      return Responder.respond(status: 404, errors: Messages::MSG_DMP_NOT_FOUND, event: event) if dmp_id.nil?

      # Fail if the DMP ID is not a valid DMP ID
      p_key = KeyHelper.path_parameter_to_pk(param: dmp_id)
      return Responder.respond(status: 400, errors: Messages::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      # Get the Version specified (if any) and validate that its the correct format
      version = nil if version == KeyHelper::DMP_LATEST_VERSION.gsub(KeyHelper::SK_DMP_PREFIX, '')
      valid_sk = "#{KeyHelper::SK_DMP_PREFIX}#{version}" =~ KeyHelper::SK_DMP_REGEX unless version.nil?
      s_key = "#{KeyHelper::SK_DMP_PREFIX}#{version}" if !version.nil? &&
                                                         (!valid_sk.nil? && valid_sk.zero?)

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)

      # Get the DMP
      finder = DmpFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = finder.find_dmp_by_pk(p_key: p_key, s_key: s_key)
      return Responder.respond(status: resp[:status], errors: resp[:error], event: event) unless resp[:status] == 200

      Responder.respond(status: 200, items: resp[:items], event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  end
end
