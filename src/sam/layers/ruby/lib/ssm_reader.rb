# frozen_string_literal: true

require 'aws-sdk-ssm'

# ----------------------------------------------------
# SSM Parameter Store Helper
#
# Shared helper methods for accessing SSM parameters
# ----------------------------------------------------
class SsmReader
  ADMINISTRATOR_EMAIL = '/uc3/dmp/hub/%{env}/AdminEmail'

  API_BASE_URL = '/uc3/dmp/hub/%{env}/ApiBaseUrl'
  BASE_URL = '/uc3/dmp/hub/%{env}/BaseUrl'

  DEBUG_MODE = '/uc3/dmp/hub/%{env}/Debug'

  DMP_ID_API_URL = '/uc3/dmp/hub/%{env}/EzidApiUrl'
  DMP_ID_BASE_URL = '/uc3/dmp/hub/%{env}/EzidBaseUrl'
  DMP_ID_CLIENT_ID = '/uc3/dmp/hub/%{env}/EzidUsername'
  DMP_ID_CLIENT_NAME = '/uc3/dmp/hub/%{env}/EzidHostingInstitution'
  DMP_ID_CLIENT_SECRET = '/uc3/dmp/hub/%{env}/EzidPassword'
  DMP_ID_DEBUG_MODE = '/uc3/dmp/hub/%{env}/EzidDebugMode'
  DMP_ID_PAUSED = '/uc3/dmp/hub/%{env}/EzidPaused'
  DMP_ID_SHOULDER = '/uc3/dmp/hub/%{env}/EzidShoulder'

  PROVENANCE_API_CLIENT_ID = '/uc3/dmp/hub/%{env}/%{provenance}/client_id'
  PROVENANCE_API_CLIENT_SECRET = '/uc3/dmp/hub/%{env}/%{provenance}/client_secret'

  S3_BUCKET_URL = '/uc3/dmp/hub/%{env}/S3CloudFrontBucketUrl'
  S3_ACCESS_POINT = '/uc3/dmp/hub/%{env}/S3CloudFrontBucketAccessPoint'

  TABLE_NAME = '/uc3/dmp/hub/%{env}/DynamoTableName'

  class << self
    # Fetch the value for the specified :key
    # ----------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def get_ssm_value(key:, provenance_name: nil)
      return nil unless key.is_a?(String) && key.strip.length.positive?

      key_vals = { env: ENV.fetch('LAMBDA_ENV', 'dev').to_s.downcase }
      # Swap in the provenance name if applicable
      key_vals[:provenance] = provenance_name unless provenance_name.nil? ||
                                                     !key.include?('%{provenance}')
      key = format(key, key_vals)
      resp = Aws::SSM::Client.new.get_parameter(name: key, with_decryption: true)
      resp.nil? || resp.parameter.nil? ? nil : resp.parameter.value
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(
        source: "SsmReader.get_ssm-value - looking for #{key}",
        message: e.message, details: e.backtrace
      )
      nil
    end
    # rubocop:enable Metrics/AbcSize

    # Checks to see if debug mode has been enabled in SSM
    # ----------------------------------------------------
    def debug_mode?
      get_ssm_value(key: DEBUG_MODE)&.downcase&.strip == 'true'
    end
  end
end
