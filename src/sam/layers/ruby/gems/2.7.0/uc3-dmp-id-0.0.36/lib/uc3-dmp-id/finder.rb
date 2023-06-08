# frozen_string_literal: true

require 'uc3-dmp-dynamo'

module Uc3DmpId
  class FinderError < StandardError; end

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

      # Find a DMP based on the contents of the incoming JSON
      # -------------------------------------------------------------------------
      def by_json(json:, debug: false)
        json = Helper.parse_json(json: json)&.fetch('dmp', {})
        raise FinderError, MSG_INVALID_ARGS if json.nil? || (json['PK'].nil? && json['dmp_id'].nil?)

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
        raise FinderError, MSG_MISSING_PK if p_key.nil?

        s_key = Helper::DMP_LATEST_VERSION if s_key.nil? || s_key.to_s.strip.empty?
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        resp = client.get_item(
          key: {
            PK: Helper.append_pk_prefix(p_key: p_key),
            SK: s_key
          }
        )
        return resp unless resp.is_a?(Hash)

        dmp = resp['dmp'].nil? ? JSON.parse({ dmp: resp }.to_json) : resp
        return nil if dmp['dmp']['PK'].nil?

        dmp = Versioner.append_versions(p_key: dmp['dmp']['PK'], dmp: dmp, client: client, debug: debug)
        Helper.cleanse_dmp_json(json: dmp)
      end

      # Fetch just the PK to see if a record exists
      # -------------------------------------------------------------------------
      def exists?(p_key:)
        raise FinderError, MSG_MISSING_PK if p_key.nil?

        resp = client.get_item(
          key: {
            PK: Helper.append_pk_prefix(p_key: p_key),
            SK: s_key
          },
          projection_expression: 'PK'
        )
        resp.is_a?(Hash)
      end

      # Attempt to find the DMP item by the provenance system's identifier
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def by_provenance_identifier(json:, client: nil, debug: false)
        raise FinderError, MSG_MISSING_PROV_ID if json.nil? || json.fetch('dmp_id', {})['identifier'].nil?

        args = {
          key_conditions: {
            dmphub_provenance_identifier: {
              attribute_value_list: [json['dmp_id']['identifier']],
              comparison_operator: 'EQ'
            }
          },
          filter_expression: 'SK = :version',
          expression_attribute_values: { ':version': Helper::DMP_LATEST_VERSION }
        }
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        resp = client.query(**args)
        return resp unless resp.is_a?(Hash)

        dmp = resp['dmp'].nil? ? JSON.parse({ dmp: resp }.to_json) : resp
        return nil if dmp['dmp']['PK'].nil?

        # If we got a hit, fetch the DMP and return it.
        by_pk(p_key: dmp['dmp']['PK'], s_key: dmp['dmp']['SK'])
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
