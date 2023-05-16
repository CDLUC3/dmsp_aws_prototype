# frozen_string_literal: true


# TODO: Be sure to update the API functions so that they call cleanse_dmp_json before
#       calling Uc3DmpApiCore::Responder.respond !!!!!!!!!!


module Uc3DmpId
  # Helper functions for working with DMP IDs
  class Helper
    PK_DMP_PREFIX = 'DMP#'
    PK_DMP_REGEX = %r{DMP#[a-zA-Z0-9\-_.]+/[a-zA-Z0-9]{2}\.[a-zA-Z0-9./:]+}.freeze

    SK_DMP_PREFIX = 'VERSION#'
    SK_DMP_REGEX = /VERSION#\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2}/.freeze

    # TODO: Verify the assumed structure of the DOI is valid
    DOI_REGEX = %r{[0-9]{2}\.[0-9]{5}/[a-zA-Z0-9/_.-]+}.freeze
    URL_REGEX = %r{(https?://)?([a-zA-Z0-9\-_]\.)+[a-zA-Z0-9\-_]{2,3}(:[0-9]+)?/?}.freeze

    DMP_LATEST_VERSION = "#{SK_DMP_PREFIX}latest"
    DMP_TOMBSTONE_VERSION = "#{SK_DMP_PREFIX}tombstone"

    class << self
      # Append the PK prefix for the object
      # -------------------------------------------------------------------------------------
      def append_pk_prefix(p_key:)
        p_key.is_a?(String) ? "#{PK_DMP_PREFIX}#{remove_pk_prefix(p_key: p_key)}" : nil
      end

      # Strip off the PK prefix
      # -------------------------------------------------------------------------------------
      def remove_pk_prefix(p_key:)
        p_key.is_a?(String) ? p_key.gsub(PK_DMP_PREFIX, '') : p_key
      end

      # Append the SK prefix for the object
      # -------------------------------------------------------------------------------------
      def append_sk_prefix(s_key:)
        s_key.is_a?(String) ? "#{SK_DMP_PREFIX}#{remove_pk_prefix(s_key: s_key)}" : nil
      end

      # Strip off the SK prefix
      # -------------------------------------------------------------------------------------
      def remove_sk_prefix(s_key:)
        s_key.is_a?(String) ? s_key.gsub(SK_DMP_PREFIX, '') : s_key
      end

      # Return the base URL for a DMP ID
      def dmp_id_base_url
        url = ENV.fetch('DMP_ID_BASE_URL', 'https://dmptool-dev.cdlib.org/dmps/')
        url&.end_with?('/') ? url : "#{url}/"
      end

      # Return the base URL for the API
      def api_base_url
        url = ENV.fetch('DMP_ID_BASE_URL', 'https://api.dmptool-dev.cdlib.org/dmps/')
        url&.end_with?('/') ? url : "#{url}/"
      end

      # Format the DMP ID in the way we want it
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
      def path_parameter_to_pk(param:)
        return nil unless param.is_a?(String) && !param.strip.empty?

        base_domain = dmp_id_base_url.gsub(%r{https?://}, '')
        p_key = param if param.start_with?(dmp_id_base_url) || param.start_with?(base_domain)
        p_key = CGI.unescape(p_key.nil? ? param : p_key)
        p_key = format_dmp_id(value: p_key)
        append_pk_prefix(dmp: p_key)
      end

      # Append the :PK prefix to the :dmp_id
      def dmp_id_to_pk(json:)
        return nil if json.nil? || json['identifier'].nil?

        # If it's a DOI format it correctly
        dmp_id = format_dmp_id(value: json['identifier'].to_s)
        return nil if dmp_id.nil? || dmp_id == ''

        append_pk_prefix(dmp: dmp_id)
      end

      # Derive the DMP ID by removing the :PK prefix
      def pk_to_dmp_id(p_key:)
        return nil if p_key.nil?

        {
          type: 'doi',
          identifier: format_dmp_id(value: remove_pk_prefix(dmp: p_key), with_protocol: true)
        }
      end

      # Parse the incoming JSON if necessary or return as is if it's already a Hash
      def parse_json(json:)
        return json if json.is_a?(Hash)

        json.is_a?(String) ? JSON.parse(json) : nil
      end

      # Recursive method that strips out any DMPHub related metadata from a DMP record before sending
      # it to the caller
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def cleanse_dmp_json(json:)
        return json unless json.is_a?(Hash) || json.is_a?(Array)

        # If it's an array clean each of the objects individually
        return json.map { |obj| cleanse_dmp_json(json: obj) }.compact if json.is_a?(Array)

        cleansed = {}
        allowable = %w[dmphub_versions]
        json.each_key do |key|
          next if (key.to_s.start_with?('dmphub') && !allowable.include?(key)) || %w[PK SK].include?(key.to_s)

          obj = json[key]
          # If this object is a Hash or Array then recursively cleanse it
          cleansed[key] = obj.is_a?(Hash) || obj.is_a?(Array) ? cleanse_dmp_json(json: obj) : obj
        end
        cleansed.keys.any? ? cleansed : nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
