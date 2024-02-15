# frozen_string_literal: true

require 'aws-sdk-ssm'

module Uc3DmpApiCore
  # ----------------------------------------------------
  # SSM Parameter Store Helper
  #
  # Shared helper methods for accessing SSM parameters
  # ----------------------------------------------------
  class SsmReader
    SOURCE = 'Uc3DmpApiCore::SsmReader'

    class << self
      # Return all of the available keys
      def available_keys
        _ssm_keys.keys
      end

      # Fetch the value for the specified :key
      # ----------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def get_ssm_value(key:, provenance_name: nil, logger: nil)
        full_key = _ssm_keys[:"#{key.downcase}"] unless key.nil?
        logger&.debug(message: "Looking for SSM Key: #{full_key}")
        return nil if full_key.nil?

        key_vals = { env: ENV.fetch('LAMBDA_ENV', 'dev').to_s.downcase }
        # Swap in the provenance name if applicable
        key_vals[:provenance] = provenance_name unless provenance_name.nil? ||
                                                       !full_key.include?('%{provenance}')
        fetch_value(key: format(full_key, key_vals), logger:)
      rescue Aws::Errors::ServiceError => e
        logger&.error(message: "Looking for SSM Key: #{key} - #{e.message}", details: e.backtrace)
        nil
      end
      # rubocop:enable Metrics/AbcSize

      # Call SSM to get the value for the specified key
      def fetch_value(key:, logger: nil)
        resp = Aws::SSM::Client.new.get_parameter(name: key, with_decryption: true)
        logger&.debug(message: "Searching for SSM Key: #{key}, Found: '#{resp&.parameter&.value}'")
        resp.nil? || resp.parameter.nil? ? nil : resp.parameter.value
      end

      private

      # DMPTool/DMPHub SSM keys. See the installation guide for information about how these values are used
      #    https://github.com/CDLUC3/dmp-hub-cfn/wiki/installation-and-setup#required-ssm-parameters
      def _ssm_keys
        {
          administrator_email: '/uc3/dmp/hub/%{env}/AdminEmail',
          api_base_url: '/uc3/dmp/hub/%{env}/ApiBaseUrl',
          base_url: '/uc3/dmp/hub/%{env}/BaseUrl',

          dmp_id_api_url: '/uc3/dmp/hub/%{env}/EzidApiUrl',
          dmp_id_base_url: '/uc3/dmp/hub/%{env}/EzidBaseUrl',
          dmp_id_client_id: '/uc3/dmp/hub/%{env}/EzidUsername',
          dmp_id_client_name: '/uc3/dmp/hub/%{env}/EzidHostingInstitution',
          dmp_id_client_secret: '/uc3/dmp/hub/%{env}/EzidPassword',
          dmp_id_debug_mode: '/uc3/dmp/hub/%{env}/EzidDebugMode',
          dmp_id_paused: '/uc3/dmp/hub/%{env}/EzidPaused',
          dmp_id_shoulder: '/uc3/dmp/hub/%{env}/EzidShoulder',

          provenance_api_client_id: '/uc3/dmp/hub/%{env}/%{provenance}/client_id',
          provenance_api_client_secret: '/uc3/dmp/hub/%{env}/%{provenance}/client_secret',

          s3_bucket_url: '/uc3/dmp/hub/%{env}/S3CloudFrontBucketUrl',
          s3_access_point: '/uc3/dmp/hub/%{env}/S3CloudFrontBucketAccessPoint',

          rds_username: '/uc3/dmp/tool/%{env}/RdsUsername',
          rds_password: '/uc3/dmp/tool/%{env}/RdsPassword',

          dynamo_table_name: '/uc3/dmp/hub/%{env}/DynamoTableName'
        }
      end
    end
  end
end
