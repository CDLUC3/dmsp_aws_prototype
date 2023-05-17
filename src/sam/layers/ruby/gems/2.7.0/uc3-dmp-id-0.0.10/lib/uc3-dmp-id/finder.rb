# frozen_string_literal: true

require 'uc3-dmp-dynamo'

module Uc3DmpId
  class Uc3DmpIdFinderError < StandardError; end

  # Methods to find/search for DMP IDs
  class Finder
    MSG_INVALID_ARGS = 'Expected JSON to be structured as `{ "dmp": { "PK": "value"} } OR \
                        { "dmp": { "dmp_id": { "identifier": "value", "type": "value" } }`'
    MSG_MISSING_PK = 'No PK was provided'
    MSG_MISSING_PROV_ID = 'No Provenance identifier was provided. \
                           Expected: `{ "dmp_id": { "identifier": "value", "type": "value" }`'

    class << self
      # TODO: Replace this with ElasticSearch
      def search_dmps(**_args)

        # TODO: Need to move this to ElasticSearch!!!
      end
      # rubocop:enable Metrics/MethodLength

      # Find the DMP's versions
      # -------------------------------------------------------------------------
      def versions(p_key:, client: nil, debug: false)
        raise Uc3DmpIdFinderError, MSG_MISSING_PK if p_key.nil?

        args = {
          key_conditions: {
            PK: { attribute_value_list: [Helper.append_pk_prefix(dmp: p_key)], comparison_operator: 'EQ' }
          },
          projection_expression: 'modified',
          scan_index_forward: false
        }
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        client.query(**args)
      end

      # Find a DMP based on the contents of the incoming JSON
      # -------------------------------------------------------------------------
      def by_json(json:, debug: false)
        json = Validator.parse_json(json: json)&.fetch('dmp', {})
        raise Uc3DmpIdFinderError, MSG_INVALID_ARGS if json.nil? || (json['PK'].nil? && json['dmp_id'].nil?)

        p_key = json['PK']
        # Translate the incoming :dmp_id into a PK
        p_key = Helper.dmp_id_to_pk(json: json.fetch('dmp_id', {})) if p_key.nil?
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client

        # find_by_dmphub_provenance_id -> if no PK and no dmp_id result
        return by_provenance_identifier(json: json, client: client, debug: debug) if p_key.nil?

        # find_by_PK
        by_pk(p_key: p_key, s_key: json['SK'], client: client, debug: debug)
      end

      # Find the DMP by its PK and SK
      # -------------------------------------------------------------------------
      def by_pk(p_key:, s_key: Helper::DMP_LATEST_VERSION, client: nil, debug: false)
        raise Uc3DmpIdFinderError, MSG_MISSING_PK if p_key.nil?

        s_key = Helper::DMP_LATEST_VERSION if s_key.nil? || s_key.strip.empty?

        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        resp = client.get_item(
          key: {
            PK: Helper.append_pk_prefix(dmp: p_key),
            SK: s_key.nil? || s_key.strip.empty? ? Helper::DMP_LATEST_VERSION : s_key
          }
        )
        return nil if resp.nil? || resp.fetch('dmp', {})['PK'].nil?

        _append_versions(p_key: resp['dmp']['PK'], dmp: resp, client: client, debug: debug)
      end

      # Attempt to find the DMP item by the provenance system's identifier
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def by_provenance_identifier(json:, client: nil, debug: false)
        raise Uc3DmpIdFinderError, MSG_MISSING_PROV_ID if json.nil? || json.fetch('dmp_id', {})['identifier'].nil?

        args = {
          key_conditions: {
            dmphub_provenance_identifier: {
              attribute_value_list: [json['dmp_id']['identifier']],
              comparison_operator: 'EQ'
            }
          },
          filter_expression: 'SK = :version',
          expression_attribute_values: { ':version': KeyHelper::DMP_LATEST_VERSION }
        }
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        resp = client.query(**args)
        return resp if resp.nil? || resp['dmp'].nil?

        # If we got a hit, fetch the DMP and return it.
        by_pk(p_key: resp['dmp']['PK'], s_key: resp['dmp']['SK'])
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Build the dmphub_versions array and attach it to the dmp
      # rubocop:disable Metrics/AbcSize
      def _append_versions(p_key:, dmp:, client: nil, debug: false)
        return dmp if p_key.nil? || !dmp.is_a?(Hash) || dmp['dmp'].nil?

        results = versions(p_key: p_key, client: client, debug: debug)
        return dmp unless results.length > 1

        versions = results.map do |version|
          next if version.fetch('dmp', {})['modified'].nil?

          timestamp = version['dmp']['modified']
          {
            timestamp: timestamp,
            url: "#{Helper.api_base_url}dmps/#{Helper.remove_pk_prefix(dmp: p_key)}?version=#{timestamp}"
          }
        end
        dmp['dmp']['dmphub_versions'] = JSON.parse(versions.to_json)
        dmp
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
