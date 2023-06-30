# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-s3'

require 'base64'

module Functions
  # A Proxy service that queries the NIH Awards API and transforms the results into a common format
  class GetNarrative
    SOURCE = 'GET /narratives?dmp_id={dmp_id+}'

    MSG_BAD_ARGS = 'Expecting a narrative id (e.g. 1234567890abcd.pdf)'

    def self.process(event:, context:)
      params = event.fetch('pathParameters', {})
      id = params.fetch('narrative_id', '')
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) if id.strip.empty?

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Store the document in S3 Bucket
      payload = Uc3DmpS3::Client.get_narrative(key: id)
      return _respond(status: 404, errors: Uc3DmpApiCore::MSG_NOT_FOUND, event: event) if payload.nil?

      # Return the narrative document
      # The Base64 encoded body lets API Gateway know to return this as a binary rather than json
      {
        statusCode: 200,
        body: payload,
        isBase64Encoded: true,
        headers: { 'Content-Type': 'application/pdf' }
      }
    rescue Aws::Errors::ServiceError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder.rb that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

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