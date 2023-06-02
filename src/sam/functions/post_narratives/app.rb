# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-s3'

module Functions
  # A Proxy service that queries the NIH Awards API and transforms the results into a common format
  class PostNarratives
    SOURCE = 'POST /narratives'

    MSG_BAD_ARGS = 'Expecting multipart/form-data with PDF content in the body'

    def self.process(event:, context:)
      # Parameters
      # ----------
      # event: Hash, required
      #     API Gateway Lambda Proxy Input Format
      #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

      # context: object, required
      #     Lambda Context runtime methods and attributes
      #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

      # Expecting the request to include the PDF:
      #
      #
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
      params = _parse_params(event: event)
      continue = params[:payload].length.positive?
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) unless params[:payload].length.positive?

      principal = event.fetch('requestContext', {}).fetch('authorizer', {})
      return _respond(status: 401, errors: [Uc3DmpRds::MSG_MISSING_USER], event: event) if principal.nil? ||
                                                                                           principal['mbox'].nil?

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Store the document in S3 Bucket
      object_key = Uc3DmpS3::Client.put_narrative(document: params[:payload], base64: params[:base64encoded])
      return _respond(status: 500, errors: Uc3DmpS3::Client::MSG_S3_FAILURE, event: event) if object_key.nil?

      Uc3DmpApiCore::LogWriter.log_message(source: SOURCE, message: "Added #{object_key} to S3") if debug

      # Generate the S3 access URL and hash for the DMP ID record
      _respond(status: 201, items: [_generate_response(object_key: object_key)], event: event)
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
      # Parse the incoming query string arguments
      def _parse_params(event:)
        return {} unless event.is_a?(Hash) &&
                         event.fetch('headers', {})['content-type']&.start_with?('multipart/form-data')

        {
          payload: event.fetch('body', ''),
          base64encoded: event.fetch('isBase64Encoded', false)
        }
      end

      # Generate the response hash.
      #
      # {
      #   "dmproadmap_related_identifiers": [
      #     {
      #       "descriptor": "is_metadata_for",
      #       "work_type": "output_management_plan",
      #       "type": "url",
      #       "identifier": "https://api.dmphub-dev.cdlib.org/narratives/83t838t83t.pdf"
      #     }
      #   ]
      # }
      def _generate_response(object_key:)
        return {} unless object_key.is_a?(String) && !object_key.strip.empty?

        api_url = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :api_base_url)
        return {} if api_url.nil?

        {
          dmproadmap_related_identifiers: [
            {
              descriptor: 'is_metadata_for',
              work_type: 'output_management_plan',
              type: 'url',
              identifier: "#{api_url}/#{object_key}"
            }
          ]
        }
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