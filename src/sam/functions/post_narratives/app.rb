# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'
require 'uc3-dmp-s3'

module Functions
  # A Proxy service that queries the NIH Awards API and transforms the results into a common format
  class PostNarratives
    SOURCE = 'POST /narratives'

    MSG_BAD_ARGS = 'Expecting multipart/form-data with PDF content in the body.'
    MSG_UNABLE_TO_ATTACH = 'Unable to save the narrative document and attach it to the DMP ID.'

    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      params = _parse_params(event: event)
      continue = params[:dmp_id].length.positive? && params[:payload].length.positive?
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) unless continue

      _set_env(logger: logger)

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger: logger)
      return _respond(status: 403, errors: Uc3DmpId::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Make sure there is a DMP ID for the narrative to be attached to!
      dmp = Uc3DmpId::Finder.by_pk(p_key: params[:dmp_id], logger: logger)
      return _respond(status: 403, errors: [Uc3DmpId::MSG_DMP_FORBIDDEN], event: event) if dmp.nil?

      # Store the document in S3 Bucket
      object_key = Uc3DmpS3::Client.put_narrative(document: params[:payload], dmp_id: params[:dmp_id], base64: params[:base64encoded])
      return _respond(status: 500, errors: Uc3DmpS3::Client::MSG_S3_FAILURE, event: event) if object_key.nil?

      # Attach the S3 access URL to the DMP ID record
      url = "#{Uc3DmpApiCore::SsmReader.get_ssm_value(key: :api_base_url, logger: logger).gsub('api.', '')}/#{object_key}"
      attached = Uc3DmpId::Updater.attach_narrative(provenance: provenance, p_key: params[:dmp_id], url: url, logger: logger)
      return _respond(status: 500, errors: [MSG_UNABLE_TO_ATTACH], event: event) unless attached

      # Reload the DMP ID and return it. It should now have a new dmproadmap_related_identifier pointing to the PDF
      logger.debug(message: "Added #{object_key} to S3", details: attached) if debug
      dmp = Uc3DmpId::Finder.by_pk(p_key: params[:dmp_id], logger: logger)
      _respond(status: 201, items: [dmp], event: event)
    rescue Aws::Errors::ServiceError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue Uc3DmpId::UpdaterError => e
      _respond(status: 400, errors: [e.message], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder.rb that failed
      logger.error(message: e.message, details: e.backtrace)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

    private

    class << self
      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger: nil)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger: logger)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger: logger)
      end

      # Parse the incoming query string arguments
      def _parse_params(event:)
        return {} unless event.is_a?(Hash) &&
                         !event.fetch('queryStringParameters', {})['dmp_id'].nil?

        {
          dmp_id: event.fetch('queryStringParameters', {})['dmp_id'],
          payload: event.fetch('body', ''),
          base64encoded: event.fetch('isBase64Encoded', false)
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