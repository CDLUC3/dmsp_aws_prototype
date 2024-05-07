# frozen_string_literal: true

# TODO: Be sure to update the API functions so that they call cleanse_dmp_json before
#       calling Uc3DmpApiCore::Responder.respond !!!!!!!!!!

module Uc3DmpId
  # Helper functions for working with DMP IDs
  class Helper
    PK_DMP_PREFIX = 'DMP#'
    PK_DMP_REGEX = %r{DMP#[a-zA-Z0-9\-_.]+/[a-zA-Z0-9]{2}\.[a-zA-Z0-9./:]+}

    SK_DMP_PREFIX = 'VERSION#'
    SK_DMP_REGEX = /VERSION#\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+\d{2}:\d{2}/

    SK_HARVESTER_MODS = "HARVESTER_MODS"

    # TODO: Verify the assumed structure of the DOI is valid
    DOI_REGEX = %r{[0-9]{2}\.[0-9]{4,}/[a-zA-Z0-9/_.-]+}
    URL_REGEX = %r{(https?://)?([a-zA-Z0-9\-_]\.)+[a-zA-Z0-9\-_]{2,3}(:[0-9]+)?/?}

    DMP_LATEST_VERSION = "#{SK_DMP_PREFIX}latest".freeze
    DMP_TOMBSTONE_VERSION = "#{SK_DMP_PREFIX}tombstone".freeze

    DEFAULT_API_URL = 'https://api.dmphub.uc3dev.cdlib.net/dmps/'
    DEFAULT_LANDING_PAGE_URL = 'https://dmphub.uc3dev.cdlib.net/dmps/'

    MSG_DMP_EXISTS = 'DMP already exists. Try :update instead.'
    MSG_DMP_FORBIDDEN = 'You do not have permission.'
    MSG_DMP_INVALID_DMP_ID = 'Invalid DMP ID format.'
    MSG_DMP_NO_DMP_ID = 'A DMP ID could not be registered at this time.'
    MSG_DMP_NO_HISTORICALS = 'You cannot modify a historical version of the DMP.'
    MSG_DMP_NO_TOMBSTONE = 'Unable to tombstone the DMP ID at this time.'
    MSG_DMP_NO_UPDATE = 'Unable to update the DMP ID at this time.'
    MSG_DMP_NOT_FOUND = 'DMP does not exist.'
    MSG_DMP_UNABLE_TO_VERSION = 'Unable to version this DMP.'
    MSG_DMP_UNKNOWN = 'DMP does not exist. Try :create instead.'
    MSG_NO_CHANGE = 'The updated record has no changes.'
    MSG_NO_OWNER_ORG = 'Could not determine ownership of the DMP ID.'
    MSG_NO_PROVENANCE_OWNER = 'Unable to determine the provenance of the DMP ID.'
    MSG_SERVER_ERROR = 'Something went wrong.'

    class << self
      # Append the PK prefix for the object
      # -------------------------------------------------------------------------------------
      def append_pk_prefix(p_key:)
        p_key.is_a?(String) ? "#{PK_DMP_PREFIX}#{remove_pk_prefix(p_key:)}" : nil
      end

      # Strip off the PK prefix
      # -------------------------------------------------------------------------------------
      def remove_pk_prefix(p_key:)
        p_key.is_a?(String) ? p_key.gsub(PK_DMP_PREFIX, '') : p_key
      end

      # Append the SK prefix for the object
      # -------------------------------------------------------------------------------------
      def append_sk_prefix(s_key:)
        s_key.is_a?(String) ? "#{SK_DMP_PREFIX}#{remove_sk_prefix(s_key:)}" : nil
      end

      # Strip off the SK prefix
      # -------------------------------------------------------------------------------------
      def remove_sk_prefix(s_key:)
        s_key.is_a?(String) ? s_key.gsub(SK_DMP_PREFIX, '') : s_key
      end

      # Return the base URL for a DMP ID
      def dmp_id_base_url
        url = ENV.fetch('DMP_ID_BASE_URL', DEFAULT_LANDING_PAGE_URL)
        url&.end_with?('/') ? url : "#{url}/"
      end

      # The landing page URL (NOT the DOI URL)
      def landing_page_url
        url = ENV.fetch('DMP_ID_LANDING_URL', DEFAULT_LANDING_PAGE_URL)
        url&.end_with?('/') ? url : "#{url}/"
      end

      # Format the DMP ID in the way we want it
      def format_dmp_id(value:, with_protocol: false)
        dmp_id = value.match(DOI_REGEX).to_s
        return nil if dmp_id.nil? || dmp_id == ''
        # If it's already a URL, return it as is
        return with_protocol ? value : value.gsub(%r{https?://}, '') if value.start_with?('http')

        dmp_id = dmp_id.gsub('doi:', '')
        dmp_id = dmp_id[1..dmp_id.length] if dmp_id.start_with?('/')
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
        append_pk_prefix(p_key:)
      end

      # Append the :PK prefix to the :dmp_id
      def dmp_id_to_pk(json:)
        return nil if !json.is_a?(Hash) || json['identifier'].nil?

        # If it's a DOI format it correctly
        dmp_id = format_dmp_id(value: json['identifier'].to_s)
        return nil if dmp_id.nil? || dmp_id == ''

        append_pk_prefix(p_key: dmp_id.gsub(%r{https?://}, ''))
      end

      # Derive the DMP ID by removing the :PK prefix
      def pk_to_dmp_id(p_key:)
        return nil if p_key.nil?

        {
          type: 'doi',
          identifier: format_dmp_id(value: remove_pk_prefix(p_key:), with_protocol: true)
        }
      end

      # Parse the incoming JSON if necessary or return as is if it's already a Hash
      def parse_json(json:)
        return json if json.is_a?(Hash)

        json.is_a?(String) ? JSON.parse(json) : nil
      end

      # Compare the DMP IDs to see if they are the same
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
        %w[SK dmphub_modification_day modified created dmphub_versions].each do |key|
          a['dmp'].delete(key) unless a['dmp'][key].nil?
          b['dmp'].delete(key) unless b['dmp'][key].nil?
        end
        a == b
      end

      # Extract the Contact's ORCID id
      def extract_owner_id(json: {})
        return nil unless json.is_a?(Hash)

        dmp = json['dmp'].nil? ? json : json['dmp']
        id = dmp.fetch('contact', {}).fetch('contact_id', {})['identifier']
        return id unless id.nil?

        dmp.fetch('contributor', []).map { |contributor| contributor.fetch('contributor_id', {})['identifier'] }.first
      end

      # Extract the Contact's affiliaiton ROR ID
      def extract_owner_org(json: {})
        return nil unless json.is_a?(Hash)

        dmp = json['dmp'].nil? ? json : json['dmp']
        owner_org = dmp.fetch('contact', {}).fetch('dmproadmap_affiliation', {}).fetch('affiliation_id',
                                                                                       {})['identifier']
        return owner_org unless owner_org.nil?

        orgs = dmp.fetch('contributor', []).map do |contributor|
          contributor.fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
        end
        orgs.compact.max_by { |i| orgs.count(i) }
      end
      # rubocop:enable Metrics/AbcSize

      # Add DMPHub specific fields to the DMP ID JSON
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def annotate_dmp_json(provenance:, p_key:, json:)
        json = parse_json(json:)
        bool_vals = [1, '1', true, 'true', 'yes']
        return json if provenance.nil? || p_key.nil? || !json.is_a?(Hash)

        # Fail the json as is if the :PK does not match the :dmp_id if the json has a :PK
        id = dmp_id_to_pk(json: json.fetch('dmp_id', {}))
        return json if id != p_key && !json['PK'].nil?

        annotated = deep_copy_dmp(obj: json)
        annotated['PK'] = json['PK'] || append_pk_prefix(p_key:)
        annotated['SK'] = DMP_LATEST_VERSION

        # Ensure that the :dmp_id matches the :PK
        annotated['dmp_id'] = JSON.parse(pk_to_dmp_id(p_key: remove_pk_prefix(p_key: annotated['PK'])).to_json)

        owner_id = extract_owner_id(json:)
        owner_org = extract_owner_org(json:)

        # Set the :dmproadmap_featured flag appropriately
        featured = annotated.fetch('dmproadmap_featured', 'no')
        annotated['dmproadmap_featured'] = bool_vals.include?(featured.to_s.downcase) ? '1' : '0'

        # Update the modification timestamps
        annotated['dmphub_modification_day'] = Time.now.utc.strftime('%Y-%m-%d')
        annotated['dmphub_owner_id'] = owner_id unless owner_id.nil?
        annotated['dmphub_owner_org'] = owner_org unless owner_org.nil?
        annotated['registered'] = annotated['modified'] if annotated['registered'].nil?
        return annotated unless json['dmphub_provenance_id'].nil?

        annotated['dmphub_provenance_id'] = provenance.fetch('PK', '')
        return annotated if !annotated['dmphub_provenance_identifier'].nil? ||
                            json.fetch('dmp_id', {})['identifier'].nil?

        # Record the original Provenance system's identifier
        # If we are currently seeding records for existing DMP IDs, then use the :dmproadmap_links
        if provenance.fetch('seedingWithLiveDmpIds', false).to_s.downcase == 'true' &&
           !annotated.fetch('dmproadmap_links', {})['get'].nil?
          annotated['dmphub_provenance_identifier'] = annotated.fetch('dmproadmap_links', {})['get']
        else
          annotated['dmphub_provenance_identifier'] = format_provenance_id(
            provenance:, value: json.fetch('dmp_id', {})['identifier']
          )
        end
        annotated
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Recursive method that strips out any DMPHub related metadata from a DMP record before sending
      # it to the caller
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def cleanse_dmp_json(json:)
        return json unless json.is_a?(Hash) || json.is_a?(Array)
        # If it's an array clean each of the objects individually
        return json.map { |obj| cleanse_dmp_json(json: obj) }.compact if json.is_a?(Array)

        cleansed = {}
        allowable = %w[dmphub_modifications dmphub_versions]
        json.each_key do |key|
          next if (key.to_s.start_with?('dmphub') && !allowable.include?(key)) || %w[PK SK].include?(key.to_s)

          obj = json[key]
          # If this object is a Hash or Array then recursively cleanse it
          cleansed[key] = obj.is_a?(Hash) || obj.is_a?(Array) ? cleanse_dmp_json(json: obj) : obj
        end
        cleansed.keys.any? ? cleansed : nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Extracts the related identifiers that we can fetch a citation for
      def citable_related_identifiers(dmp:)
        return [] unless dmp.is_a?(Hash)

        related_identifiers = dmp.fetch('dmproadmap_related_identifiers', [])
        # Ignore the identifier that points to the narrative PDF document and any identifiers that
        # we have already fetched the citation for
        related_identifiers.reject do |id|
          (id['work_type'] == 'output_management_plan' && id['descriptor'] == 'is_metadata_for') ||
            (id['type'] == 'doi' && !id['citation'].nil?)
        end
      end

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
