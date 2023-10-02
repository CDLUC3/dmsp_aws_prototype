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
  # The lambda handler for: POST /dmps
  class PostDmps
    SOURCE = 'POST /dmps'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      body = event.fetch('body', '')
      return _respond(status: 400, errors: Uc3DmpId::Validator::MSG_EMPTY_JSON, event: event) if body.to_s.strip.empty?
      json = Uc3DmpId::Helper.parse_json(json: body)

      _set_env(logger: logger)

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger: logger)
      return _respond(status: 403, errors: Uc3DmpId::Helper::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Register a new DMP ID
      resp = Uc3DmpId::Creator.create(provenance: provenance, json: json, logger: logger)
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID) if resp.nil?

      _respond(status: 201, items: [resp], event: event)
    rescue Uc3DmpId::CreatorError => e
      _respond(status: 400, errors: [Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID, e.message], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      deets = { message: e.message, body: body }
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event: event)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    class << self

      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger: nil)
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
