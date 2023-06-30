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
        s_key.is_a?(String) ? "#{SK_DMP_PREFIX}#{remove_sk_prefix(s_key: s_key)}" : nil
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
        append_pk_prefix(p_key: p_key)
      end

      # Append the :PK prefix to the :dmp_id
      def dmp_id_to_pk(json:)
        return nil if json.nil? || json['identifier'].nil?

        # If it's a DOI format it correctly
        dmp_id = format_dmp_id(value: json['identifier'].to_s)
        return nil if dmp_id.nil? || dmp_id == ''

        append_pk_prefix(p_key: dmp_id)
      end

      # Derive the DMP ID by removing the :PK prefix
      def pk_to_dmp_id(p_key:)
        return nil if p_key.nil?

        {
          type: 'doi',
          identifier: format_dmp_id(value: remove_pk_prefix(p_key: p_key), with_protocol: true)
        }
      end

      # Parse the incoming JSON if necessary or return as is if it's already a Hash
      def parse_json(json:)
        return json if json.is_a?(Hash)

        json.is_a?(String) ? JSON.parse(json) : nil
      end

      # Compare the DMP IDs to see if they are the same
      def eql?(dmp_a:, dmp_b:)
        return dmp_a == dmp_b unless dmp_a.is_a?(Hash) && !dmp_a['dmp'].nil? && dmp_b.is_a?(Hash) && !dmp_b['dmp'].nil?

        # return true if they're identical
        return true if dmp_a == dmp_b

        # If the PK do not match, then they are not equivalent!
        return false unless dmp_a.is_a?(Hash) && dmp_a['dmp'].fetch('PK', '').start_with?(Helper::PK_DMP_PREFIX) &&
                            dmp_b.is_a?(Hash) && dmp_b['dmp'].fetch('PK', '').start_with?(Helper::PK_DMP_PREFIX) &&
                            dmp_a['dmp']['PK'] == dmp_b['dmp']['PK']

        a = deep_copy_dmp(obj: dmp_a)
        b = deep_copy_dmp(obj: dmp_b)

        # ignore some of the attributes before comparing
        %w[SK dmphub_modification_day dmphub_updated_at dmphub_created_at].each do |key|
        a['dmp'].delete(key) unless a['dmp'][key].nil?
        b['dmp'].delete(key) unless b['dmp'][key].nil?
        end
        a == b
      end

      # Extract the Contact's ORCID id
      def extract_owner_id(json: {})
        return nil unless json.is_a?(Hash)

        dmp = json['dmp'].nil? ? json : json['dmp']
        owner_org = dmp.fetch('contact', {}).fetch('contact_id', {})['identifier']

        orgs = dmp.fetch('contributor').map do { |contributor| contributor.fetch('contact_id', {})['identifier'] }
        orgs.first
      end

      # Extract the Contact's affiliaiton ROR ID
      def extract_owner_org(json: {})
        return nil unless json.is_a?(Hash)

        dmp = json['dmp'].nil? ? json : json['dmp']
        owner_org = dmp.fetch('contact', {}).fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
        return owner_org unless owner_org.nil?

        orgs = dmp.fetch('contributor').map do |contributor|
          contributor.fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
        end
        orgs.compact.max_by { |i| orgs.count(i) }
      end

      # Add DMPHub specific fields to the DMP ID JSON
      def annotate_dmp_json(provenance:, p_key:, json:)
        json = parse_json(json: json)
        return json if provenance.nil? || owner_org.nil? || p_key.nil? || !json.is_a?(Hash)

        # Fail the json as is if the :PK does not match the :dmp_id if the json has a :PK
        id = dmp_id_to_pk(json: json.fetch('dmp_id', {}))
        return json if id != p_key && !json['PK'].nil?

        annotated = deep_copy_dmp(obj: json)
        annotated['PK'] = json['PK'] || append_pk_prefix(p_key: p_key)
        annotated['SK'] = DMP_LATEST_VERSION

        # Ensure that the :dmp_id matches the :PK
        annotated['dmp_id'] = pk_to_dmp_id(p_key: remove_pk_prefix(p_key: annotated['PK']))

        owner_id = extract_owner_id(json: json)
        owner_org = extract_owner_org(json: json)

        # Update the modification timestamps
        annotated['dmphub_modification_day'] = Time.now.strftime('%Y-%m-%d')
        annotated['dmphub_owner_id'] = owner_id unless owner_id.nil?
        annotated['dmphub_owner_org'] = owner_org unless owner_org.nil?
        annotated['dmphub_updated_at'] = Time.now.iso8601
        # Only add the Creation date if it is blank
        annotated['dmphub_created_at'] = Time.now.iso8601 if json['dmphub_created_at'].nil?
        return annotated unless json['dmphub_provenance_id'].nil?

        annotated['dmphub_provenance_id'] = provenance.fetch('PK', '')
        return annotated if !annotated['dmphub_provenance_identifier'].nil? ||
                            json.fetch('dmp_id', {})['identifier'].nil?

        # Record the original Provenance system's identifier
        annotated['dmphub_provenance_identifier'] = format_provenance_id(
          provenance: provenance, value: json.fetch('dmp_id', {})['identifier']
        )
        annotated
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

      # Ruby's clone/dup methods do not clone/dup the children, so we need to do it here
      # --------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def deep_copy_dmp(obj:)
        case obj.class.name
        when 'Array'
          obj.map { |item| deep_copy_dmp(obj: item) }
        when 'Hash'
          hash = obj.dup
          hash.each_pair do |key, value|
            if key.is_a?(::String) || key.is_a?(::Symbol)
              hash[key] = deep_copy_dmp(obj: value)
            else
              hash.delete(key)
              hash[deep_copy_dmp(obj: key)] = deep_copy_dmp(obj: value)
            end
          end
          hash
        else
          obj.dup
        end
      end
      # rubocop:enable Metrics/AbcSize

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
        id = provenance['PK']&.gsub('PROVENANCE#', '')
        "#{id}##{val}"
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
