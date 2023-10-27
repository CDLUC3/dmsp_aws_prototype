# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'

module Functions
  # The handler for PUT /dmps/{dmp_id+}
  class PutDmp
    SOURCE = 'PUT /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

      # Get the params
      params = event.fetch('pathParameters', {})
      dmp_id = params['dmp_id']
      body = event.fetch('body', '')
      return _respond(status: 400, errors: Uc3DmpId::Validator::MSG_EMPTY_JSON, event:) if body.to_s.strip.empty?

      json = Uc3DmpId::Helper.parse_json(json: body)
      # Fail if the DMP ID is not a valid DMP ID
      p_key = Uc3DmpId::Helper.path_parameter_to_pk(param: dmp_id)
      p_key = Uc3DmpId::Helper.append_pk_prefix(p_key:) unless p_key.nil?
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_INVALID_DMP_ID, event:) if p_key.nil?

      _set_env(logger:)

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger:)
      return _respond(status: 403, errors: Uc3DmpId::Helper::MSG_DMP_FORBIDDEN, event:) if provenance.nil?

      logger.debug(message: "Attempting update to PK: #{p_key}", details: json) if logger.respond_to?(:debug)

      # Update the DMP ID
      resp = Uc3DmpId::Updater.update(logger:, provenance:, p_key:, json:)
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID) if resp.nil?

      _respond(status: 200, items: [resp], event:)
    rescue Uc3DmpId::UpdaterError => e
      _respond(status: 400, errors: [Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID, e.message], event:)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      deets = { message: e.message, dmp_id: p_key, body: }
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    class << self
      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger:)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger:)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger:)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status:, items:, errors:, event:,
          page: params['page'], per_page: params['per_page']
        )
      end
    end
  end
end
