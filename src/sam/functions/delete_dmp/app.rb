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
  # The lambda handler for: DELETE /dmps/{dmp_id+}
  class DeleteDmp
    SOURCE = 'DELETE /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      params = event.fetch('pathParameters', {})
      dmp_id = params['dmp_id']

      # Fail if the DMP ID is not a valid DMP ID
      p_key = Uc3DmpId::Helper.path_parameter_to_pk(param: dmp_id)
      p_key = Uc3DmpId::Helper.append_pk_prefix(p_key: p_key) unless p_key.nil?
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      _set_env(logger: logger)

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger: logger)
      return _respond(status: 403, errors: Uc3DmpId::Helper::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Update the DMP ID
      resp = Uc3DmpId::Deleter.tombstone(provenance: provenance, p_key: p_key, logger: logger)
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID) if resp.nil?

      _respond(status: 200, items: [resp], event: event)
    rescue Uc3DmpId::DeleterError => e
      _respond(status: 400, errors: [Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID, e.message], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: { dmp_id: p_key }, event: event)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    class << self
      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger: logger)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger: logger)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger: logger)
      end
    end
  end
end
