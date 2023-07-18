# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-id'

module Functions
  # The handler for: GET /dmps/{dmp_id+}
  class GetDmp
    SOURCE = 'GET /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      params = event.fetch('pathParameters', {})
      qs_params = event.fetch('queryStringParameters', {})
      request_id = context.aws_request_id if context.is_a?(LambdaContext)

      dmp_id = params['dmp_id']
      s_key = qs_params&.fetch('version', _version_from_path(dmp_id: dmp_id)) unless dmp_id.nil?
      s_key = Uc3DmpId::Helper.append_sk_prefix(s_key: s_key) unless s_key.nil?
      return _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS], event: event) if dmp_id.nil?

      # Fail if the DMP ID is not a valid DMP ID
      p_key = Uc3DmpId::Helper.path_parameter_to_pk(param: dmp_id)
      p_key = Uc3DmpId::Helper.append_pk_prefix(p_key: p_key) unless p_key.nil?
      return _respond(status: 400, errors: Uc3DmpId::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      # Fetch SSM parameters and set them in the ENV
      _set_env(logger: logger)

      # Get the DMP
      logger.debug(message: "Searching for PK: #{p_key}, SK: #{s_key}") if logger.respond_to?(:debug)
      result = Uc3DmpId::Finder.by_pk(p_key: p_key, s_key: s_key, logger: logger)
      logger.debug(message: 'Found the following result:', details: result) if logger.respond_to?(:debug)
      _respond(status: 200, items: [result], event: event, params: params)
    rescue Uc3DmpId::FinderError => e
      logger.error(message: e.message, details: e.backtrace)
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
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

      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger:)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger: logger)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger: logger)
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
