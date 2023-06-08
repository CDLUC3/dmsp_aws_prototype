# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-id'

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
      qs_params = event.fetch('queryStringParameters', {})
      dmp_id = params['dmp_id']
      s_key = qs_params&.fetch('version', _version_from_path(dmp_id: dmp_id)) unless dmp_id.nil?
      s_key = Uc3DmpId::Helper.append_sk_prefix(s_key: s_key) unless s_key.nil?
      return _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS], event: event) if dmp_id.nil?

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Fail if the DMP ID is not a valid DMP ID
      p_key = Uc3DmpId::Helper.path_parameter_to_pk(param: dmp_id)
      p_key = Uc3DmpId::Helper.append_pk_prefix(p_key: p_key) unless p_key.nil?
      return _respond(status: 400, errors: Uc3DmpId::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      # Fetch SSM parameters and set them in the ENV
      _prep_env

      # Get the DMP
      result = Uc3DmpId::Finder.by_pk(p_key: p_key, s_key: s_key, debug: debug)
      _respond(status: 200, items: [result], event: event, params: params)
    # rescue Uc3DmpId::Uc3DmpIdFinderError => e
    #   Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
    #   _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    class << self
      # Rails' ActiveResource won't pass query strings, so see if its part of the path
      def _version_from_path(dmp_id:)
        ver_param = '%3Fversion%3D'
        return nil unless dmp_id&.include?(ver_param)

        CGI.unescape(dmp_id.split(ver_param).last)
      end

      # The uc3-dmp-id and uc3-dmp-dynamo gems require a few ENV variables, so set them from SSM params
      def _prep_env
        ENV['DMP_ID_API_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_api_url)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url)
        ENV['DYNAMO_TABLE'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dynamo_table_name)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status: status, items: items, errors: errors, event: event,
          page: params['page'], per_page: params['per_page']
        )
      end
    end
  end
end
