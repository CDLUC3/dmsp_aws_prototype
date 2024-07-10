# frozen_string_literal: true

require 'uc3-dmp-dynamo'
require 'securerandom'

module Uc3DmpId
  class FinderError < StandardError; end

  # Methods to find/search for DMP IDs
  class Finder
    MSG_INVALID_ARGS = 'Expected JSON to be structured as `{ "dmp": { "PK": "value"} } OR \
                        { "dmp": { "dmp_id": { "identifier": "value", "type": "value" } }`'
    MSG_INVALID_OWNER_ID = 'Invalid :owner_orcid. Expected a valid ORCID id (excluding the domain)`.'
    MSG_INVALID_OWNER_ORG = 'Invalid :owner_org_ror. Expected a valid ROR id (excluding the domain)`.'
    MSG_INVALID_MOD_DATE = 'Invalid :modification_day. Expected value to be in the `YYYY-MM-DD` format.'
    MSG_MISSING_PK = 'No PK was provided'
    MSG_MISSING_PROV_ID = 'No Provenance identifier was provided. \
                           Expected: `{ "dmp_id": { "identifier": "value", "type": "value" }`'

    ORCID_DOMAIN = 'orcid.org'
    ROR_DOMAIN = 'ror.org'

    class << self
      # TODO: Replace this with ElasticSearch
      def search_dmps(args:, logger: nil)
        client = Uc3DmpDynamo::Client.new(table: ENV['DYNAMO_INDEX_TABLE'])
        owner_pks = _by_owner(owner: args['owner'], client:, logger:) unless args['owner'].nil?
        org_pks = _by_org(org: args['org'], client:, logger:) unless args['org'].nil?
        funder_pks = _by_funder(funder: args['funder'], client:, logger:) unless args['funder'].nil?

        return _by_featured(client:, logger:) if args.fetch('featured', 'false').to_s.downcase == 'true'

        return _publicly_visible(client:, logger:)

        client = Uc3DmpDynamo::Client.new(table: ENV['DYNAMO_TABLE'])
        _fetch_dmps(client:, pks: dmps, logger:)
      end

      # Find a DMP based on the contents of the incoming JSON
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def by_json(json:, client: nil, cleanse: true, logger: nil)
        json = Helper.parse_json(json:)&.fetch('dmp', {})
        raise FinderError, MSG_INVALID_ARGS if !json.is_a?(Hash) || (json['PK'].nil? && json['dmp_id'].nil?)

        p_key = json['PK']
        # Translate the incoming :dmp_id into a PK
        p_key = Helper.dmp_id_to_pk(json: json.fetch('dmp_id', {})) if p_key.nil?
        client = Uc3DmpDynamo::Client.new if client.nil?

        # TODO: Re-enable this once we figure out Dynamo indexes
        # find_by_dmphub_provenance_id -> if no PK and no dmp_id result
        # return by_provenance_identifier(json: json, client: client, logger: logger) if p_key.nil?

        # find_by_PK
        p_key.nil? ? nil : by_pk(p_key:, s_key: json['SK'], client:, cleanse:, logger:)
      end
      # rubocop:enable Metrics/AbcSize

      # Find the DMP by its PK and SK
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def by_pk(p_key:, s_key: Helper::DMP_LATEST_VERSION, client: nil, cleanse: true, logger: nil)
        raise FinderError, MSG_MISSING_PK if p_key.nil?

        s_key = Helper::DMP_LATEST_VERSION if s_key.nil? || s_key.to_s.strip.empty?
        client = Uc3DmpDynamo::Client.new if client.nil?
        resp = client.get_item(
          key: {
            PK: Helper.append_pk_prefix(p_key:),
            SK: Helper.append_sk_prefix(s_key:)
          },
          logger:
        )
        return resp unless resp.is_a?(Hash)

        dmp = resp['dmp'].nil? ? JSON.parse({ dmp: resp }.to_json) : resp
        return nil if dmp['dmp']['PK'].nil?

        # Attach any harvester mods to the JSON
        dmp['dmp'] = _attach_harvester_mods(client:, p_key:, json: dmp['dmp'], logger:)

        dmp = Versioner.append_versions(p_key: dmp['dmp']['PK'], dmp:, client:, logger:) if cleanse
        dmp = _remove_narrative_if_private(json: dmp)
        cleanse ? Helper.cleanse_dmp_json(json: dmp) : dmp
      end
      # rubocop:enable Metrics/AbcSize

      # Fetch just the PK to see if a record exists
      # -------------------------------------------------------------------------
      def exists?(p_key:, s_key: Helper::DMP_LATEST_VERSION, client: nil, logger: nil)
        raise FinderError, MSG_MISSING_PK if p_key.nil?

        client = Uc3DmpDynamo::Client.new if client.nil?
        client.pk_exists?(
          key: {
            PK: Helper.append_pk_prefix(p_key:),
            SK: Helper.append_sk_prefix(s_key:)
          },
          logger:
        )
      end

      # Attempt to find the DMP item by the provenance system's identifier
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def by_provenance_identifier(json:, client: nil, cleanse: true, logger: nil)
        raise FinderError, MSG_MISSING_PROV_ID unless json.is_a?(Hash)

        json = json['dmp'] unless json['dmp'].nil?
        raise FinderError, MSG_MISSING_PROV_ID if json.fetch('dmp_id', {})['identifier'].nil?

        args = {
          index_name: 'dmphub_provenance_identifier_gsi',
          key_conditions: {
            dmphub_provenance_identifier: {
              attribute_value_list: [json['dmp_id']['identifier']],
              comparison_operator: 'EQ'
            }
          },
          filter_expression: 'SK = :version',
          expression_attribute_values: { ':version': Helper::DMP_LATEST_VERSION }
        }
        client = Uc3DmpDynamo::Client.new if client.nil?
        resp = client.query(args:, logger:)
        return resp unless resp.is_a?(Hash)

        dmp = resp['dmp'].nil? ? JSON.parse({ dmp: resp }.to_json) : resp
        return nil if dmp['dmp']['PK'].nil?

        # If we got a hit, fetch the DMP and return it.
        by_pk(p_key: dmp['dmp']['PK'], s_key: dmp['dmp']['SK'], cleanse:, logger:)
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Fetch the DMP IDs for the specified person's ORCID (or email)
      def _by_owner(owner:, client: nil, logger: nil)
        orcid_regex = /^([0-9a-zA-Z]{4}-){3}[0-9a-zA-Z]{4}$/
        email_regex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        orcid = owner.to_s.strip
        return [] if (orcid =~ orcid_regex).nil? && (orcid =~ email_regex).nil?

        resp = client.get_item(key: { PK: 'PERSON_INDEX', SK: orcid }, logger:)
        return resp unless resp.is_a?(Hash)

        logger&.debug(message: "DMPs for ORCID #{orcid}", details: resp)
        resp.fetch('dmps', [])
      end

      # Fetch the DMP IDs for the specified organization/institution
      def _by_org(org:, client: nil, logger: nil)
        regex = /^[a-zA-Z0-9]+$/
        ror = org.strip unless (org.to_s =~ regex).nil?

        args = {
          filter_expression: 'contains(affiliation_ids, :rors) AND SK = :sk',
          expression_attribute_values: {
            ':sk': 'METADATA',
            ':rors': [
              "http://#{ROR_DOMAIN}/#{ror}",
              "https://#{ROR_DOMAIN}/#{ror}"
            ]
          }
        }
        logger&.debug(message: 'Fetch relevant DMPs _by_org - scan args', details: args)
        client = Uc3DmpDynamo::Client.new if client.nil?
        _process_search_response(response: client.scan(args:))
      end

      # Fetch the DMP IDs for the specified funder
      def _by_funder(funder:, client: nil, logger: nil)
        regex = /^[a-zA-Z0-9]+$/
        ror = funder.strip unless (funder.to_s =~ regex).nil?

        resp = client.get_item(key: { PK: 'FUNDER_INDEX', SK: ror }, logger:)
        return [] unless resp.is_a?(Hash)

        logger&.debug(message: "DMPs for FUNDER #{ror}", details: resp)
        resp.fetch('dmps', [])
      end

      # Fetch the DMP IDs that are marked as featured
      def _by_featured(client: nil, logger: nil)
        args = {
          filter_expression: 'contains(funder_ids, :rors) AND SK = :sk',
          expression_attribute_values: {
            ':sk': 'METADATA',
            ':rors': [
              "http://#{ROR_DOMAIN}/#{ror}",
              "https://#{ROR_DOMAIN}/#{ror}"
            ]
          }
        }
        logger&.debug(message: 'Fetch relevant DMPs _by_funder - scan args', details: args)
        client = Uc3DmpDynamo::Client.new if client.nil?
        _process_search_response(response: client.scan(args:))
      end

      # Fetch the DMP IDs that are marked as featured
      def _by_featured(client: nil, logger: nil)
        args = {
          filter_expression: 'featured = :featured AND SK = :sk',
          expression_attribute_values: { ':sk': 'METADATA', ':featured': 1 }
        }
        logger&.debug(message: 'Fetch relevant DMPs _by_featured - scan args', details: args)
        client = Uc3DmpDynamo::Client.new if client.nil?
        _process_search_response(response: client.scan(args:))
      end

      # Return all of the publicly visible DMPs
      def _publicly_visible(client: nil, logger: nil)
        args = {
          filter_expression: 'visibility = :visibility AND SK = :sk',
          expression_attribute_values: { ':sk': 'METADATA', ':visibility': 'public' }
        }
        logger&.debug(message: 'Fetch relevant DMPs _publicly_visible - scan args', details: args)
        client = Uc3DmpDynamo::Client.new if client.nil?
        _process_search_response(response: client.scan(args:))
      end

      # Fetches all of the DMPs by their PKs
      def _fetch_dmps(client:, pks:, logger: null)

      end

      # Transform the search results so that we do not include any of the DMPHub specific metadata
      def _process_search_response(response:)
        return [] unless response.is_a?(Array) && response.any?

        results = response.map do |item|
          next if item.nil?

          dmp = item['dmp'].nil? ? JSON.parse({ dmp: item }.to_json) : item
          # dmp = _remove_narrative_if_private(json: dmp)
          # Helper.cleanse_dmp_json(json: dmp)
        end
        results.compact.uniq
      end

      # Remove the download URL if the DMP is private
      def _remove_narrative_if_private(json:)
        privacy_mode = json['dmp'].fetch('dmproadmap_privacy', 'private')&.downcase&.strip
        return json if privacy_mode == 'public' || json['dmp'].fetch('dmproadmap_related_identifiers', []).empty?

        json['dmp']['dmproadmap_related_identifiers'] = json['dmp']['dmproadmap_related_identifiers'].reject do |id|
          id['descriptor'] == 'is_metadata_for' && id['work_type'] == 'output_management_plan'
        end
        json
      end

      # Fetch any Harvester modifications and attach them to the JSON in the way the DMPTool expects
      # TODO: eventually just update the rebuilt DMPTool to work with the HARVESTER_MODS records as-is
      def _attach_harvester_mods(client:, p_key:, json:, logger: nil)
        # Fetch the `"SK": "HARVESTER_MODS"` record
        client = Uc3DmpDynamo::Client.new if client.nil?
        resp = client.get_item(
          key: { PK: Helper.append_pk_prefix(p_key:), SK: Helper::SK_HARVESTER_MODS }, logger:
        )
        return json unless resp.is_a?(Hash)

        mods = []
        resp.fetch('related_works', {}).each do |key, val|
          rec = val.dup
          next if rec['provenance'].nil?

          # Change the name of the `logic` array to `notes`
          rec['notes'] = rec['logic']
          rec['score'] = rec['score'].to_s
          # For `work-type` that equal `outputmanagementplan`, change it to `output_management_plan`
          rec['work_type'] = 'output_management_plan' if rec['work_type'] == 'outputmanagementplan'

          # The old `dmphub_modifications` array was grouped by provenance
          prov_array = mods.select { |entry| entry['provenance'] == rec['provenance'] }
          if prov_array.any?
            prov_array << rec
          else
            mods << {
              id: "#{Time.now.utc.strftime('%Y-%m-%d')}-#{SecureRandom.hex(4)}",
              provenance: rec['provenance'],
              augmenter_run_id: SecureRandom.hex(8),
              timestamp: rec['discovered_at'].nil? ? Time.now.utc.iso8601 : rec['discovered_at'],
              dmproadmap_related_identifiers: [rec],
              funding: []
            }
          end
        end
        # Add a `dmphub_modifications` array to the JSON
        json['dmphub_modifications'] = JSON.parse(mods.to_json)
        json
      end
    end
  end
end
