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
  # The handler for POST /dmps/validate
  class ValidateDmp
    SOURCE = 'POST /dmps/validate'

    # rubocop:disable Metrics/AbcSize
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      body = event.fetch('body', '')

      # Validate the DMP JSON
      errors = Uc3DmpId::Validator.validate(mode: 'author', json: body)
      return _respond(status: 200, items: [Uc3DmpId::Validator::MSG_VALID_JSON], event: event) if errors.is_a?(Array) &&
                                                                                                  errors.empty?
      _respond(status: 400, errors: errors, event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      deets = { message: e.message, body: body }
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event: event)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize

    private

    class << self
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
