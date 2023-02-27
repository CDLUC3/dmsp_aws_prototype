# frozen_string_literal: true

# -------------------------------------------------------------------------------------
# Key Helper
#
# Shared helper methods for Lambdas that provide tooling to deal with Dynamo PK and SK
# -------------------------------------------------------------------------------------
class KeyHelper
  PK_DMP_PREFIX = 'DMP#'
  PK_DMP_REGEX = %r{DMP#[a-zA-Z0-9\-_.]+/[a-zA-Z0-9]{2}\.[a-zA-Z0-9./:]+}.freeze

  SK_DMP_PREFIX = 'VERSION#'
  SK_DMP_REGEX = /VERSION#\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2}/.freeze

  PK_PROVENANCE_PREFIX = 'PROVENANCE#'
  SK_PROVENANCE_PREFIX = 'PROFILE'

  # TODO: Verify the assumed structure of the DOI is valid
  DOI_REGEX = %r{[0-9]{2}\.[0-9]{5}/[a-zA-Z0-9/_.-]+}.freeze
  URL_REGEX = %r{(https?://)?([a-zA-Z0-9\-_]\.)+[a-zA-Z0-9\-_]{2,3}(:[0-9]+)?/?}.freeze

  DMP_LATEST_VERSION = "#{SK_DMP_PREFIX}latest"
  DMP_TOMBSTONE_VERSION = "#{SK_DMP_PREFIX}tombstone"

  class << self
    # Return the base URL for a DMP ID
    # -------------------------------------------------------------------------------------
    def dmp_id_base_url
      url = SsmReader.get_ssm_value(key: SsmReader::DMP_ID_BASE_URL)
      url&.end_with?('/') ? url : "#{url}/"
    end

    # Return the base URL for the API
    # -------------------------------------------------------------------------------------
    def api_base_url
      url = SsmReader.get_ssm_value(key: SsmReader::DMP_ID_API_URL)
      url&.end_with?('/') ? url : "#{url}/"
    end

    # Format the DMP ID in the way we want it
    # -------------------------------------------------------------------------------------
    def format_dmp_id(value:, with_protocol: false)
      dmp_id = value.match(DOI_REGEX).to_s
      return nil if dmp_id.nil? || dmp_id == ''
      # If it's already a URL, return it as is
      return value if value.start_with?('http')

      dmp_id = dmp_id.gsub('doi:', '')
      dmp_id = dmp_id.start_with?('/') ? dmp_id[1..dmp_id.length] : dmp_id
      base_domain = with_protocol ? dmp_id_base_url : dmp_id_base_url.gsub(%r{https?://}, '')
      "#{base_domain}#{dmp_id}"
    end

    # Convert an API PathParameter (DMP ID) into a PK
    # -------------------------------------------------------------------------------------
    def path_parameter_to_pk(param:)
      return nil unless param.is_a?(String) && !param.strip.empty?

      base_domain = dmp_id_base_url.gsub(%r{https?://}, '')
      p_key = param if param.start_with?(dmp_id_base_url) || param.start_with?(base_domain)
      p_key = CGI.unescape(p_key.nil? ? param : p_key)
      p_key = format_dmp_id(value: p_key)
      append_pk_prefix(dmp: p_key)
    end

    # Append the :PK prefix to the :dmp_id
    # -------------------------------------------------------------------------------------
    def dmp_id_to_pk(json:)
      return nil if json.nil? || json['identifier'].nil?

      # If it's a DOI format it correctly
      dmp_id = format_dmp_id(value: json['identifier'].to_s)
      return nil if dmp_id.nil? || dmp_id == ''

      append_pk_prefix(dmp: dmp_id)
    end

    # Derive the DMP ID by removing the :PK prefix
    # -------------------------------------------------------------------------------------
    def pk_to_dmp_id(p_key:)
      return nil if p_key.nil?

      {
        type: 'doi',
        identifier: format_dmp_id(value: remove_pk_prefix(dmp: p_key), with_protocol: true)
      }
    end

    # Prepare the provenance identifier

    # Appends the Provenance system's identifier to the value
    #   For a DOI, it will return the DOI as-is
    #
    #   For a :provenance whose PK is 'PROVENANCE#example' and homepage is 'https://example.com' and
    #   callbackUri is 'https://example.com/callback':
    #     when the :value is '12345', it will return 'example#12345'
    #     when the :value is 'https://example.com/dmps/12345', it will return 'example#dmp/12345'
    #     when the :value is 'https://example.com/callback/12345' it will return 'example#12345'
    #
    # rubocop:disable Metrics/AbcSize
    def format_provenance_id(provenance:, value:)
      # return it as-is if there is no provenance or it's already a URL
      return value if provenance.nil?

      # return it as-is if it's a DOI
      doi = value.match(DOI_REGEX).to_s
      return value unless doi.nil? || doi == '' || !value.start_with?('http')

      # Remove the homepage or callbackUri because we will add this when needed. we just want the id
      val = value.downcase
                 .gsub(provenance.fetch('callbackUri', '').downcase, '')
                 .gsub(provenance.fetch('homepage', '').downcase, '')
      val = val.gsub(%r{https?://}, '')
      val = val[1..val.length] if val.start_with?('/')
      id = provenance['PK']&.gsub(PK_PROVENANCE_PREFIX, '')
      "#{id}##{val}"
    end
    # rubocop:enable Metrics/AbcSize

    # Append the PK prefix for the object
    # -------------------------------------------------------------------------------------
    def append_pk_prefix(dmp: nil, provenance: nil)
      # If all the :PK types were passed return nil because we only want one
      return nil if !dmp.nil? && !provenance.nil?

      dmp = dmp.gsub(%r{https?://}, '') unless dmp.nil?
      return "#{PK_DMP_PREFIX}#{remove_pk_prefix(dmp: dmp)}" unless dmp.nil?
      return "#{PK_PROVENANCE_PREFIX}#{remove_pk_prefix(provenance: provenance)}" unless provenance.nil?

      nil
    end

    # Strip off the PK prefix
    # -------------------------------------------------------------------------------------
    def remove_pk_prefix(dmp: nil, provenance: nil)
      # If all the :PK types were passed return nil because we only want one
      return nil if !dmp.nil? && !provenance.nil?

      return dmp.gsub(PK_DMP_PREFIX, '') unless dmp.nil?
      return provenance.gsub(PK_PROVENANCE_PREFIX, '') unless provenance.nil?

      nil
    end
  end
end
