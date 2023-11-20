# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-citation'
require 'uc3-dmp-cloudwatch'

module Functions
  # A service that fetches the BibTex for DOIs and converts them into citations
  class PostCitations
    SOURCE = 'POST /citations'

    MSG_INVALID_BODY = 'Invalid body! Expecting JSON like: `{"dois":[{"work_type":"dataset","value":"https://doi.org/11.1234/ab12"}]}`'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

      body = event.fetch('body', '')
      json = JSON.parse(body)
      return _respond(status: 400, errors: MSG_INVALID_BODY, event:) unless json['dois'].is_a?(Array) &&
                                                                            json['dois'].any?

      style = json['style'].nil? ? Uc3DmpCitation::Citer::DEFAULT_CITATION_STYLE : json['style'].to_s.downcase
      citations = []
      json['dois'].each do |entry|
        resp = Uc3DmpCitation::Citer.fetch_citation(doi: entry['value']&.strip, work_type: entry['work_type']&.strip,
                                                    style:, logger:)
        citations << { doi: entry['value'], citation: resp }
      end
      _respond(status: 200, items: citations, event:)
    rescue JSON::ParserError
      logger.debug(message: MSG_INVALID_BODY, details: body.to_s)
      _respond(status: 400, errors: MSG_INVALID_BODY, event:)
    rescue Uc3DmpCitation::CiterError => e
      logger.debug(message: e.message, details: body.to_s)
      _respond(status: 500, errors: e.message, event:)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      deets = { message: e.message, body: }
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    class << self
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
