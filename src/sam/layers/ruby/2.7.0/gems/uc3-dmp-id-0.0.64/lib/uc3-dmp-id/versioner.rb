# frozen_string_literal: true

require 'uc3-dmp-dynamo'

module Uc3DmpId
  class VersionerError < StandardError; end

  class Versioner
    class << self

      # Find the DMP ID's versions
      # -------------------------------------------------------------------------
      def get_versions(p_key:, client: nil, debug: false)
        return [] unless p_key.is_a?(String) && !p_key.strip.empty?

        args = {
          key_conditions: {
            PK: { attribute_value_list: [Helper.append_pk_prefix(p_key: p_key)], comparison_operator: 'EQ' }
          },
          projection_expression: 'modified',
          scan_index_forward: false
        }
        client = client.nil? ? Uc3DmpDynamo::Client.new(debug: debug) : client
        client.query(args: args, debug: debug)
      end

      # Create a new version of the DMP. This involves:
      #    - Cloning the existing `VERSION#latest` and setting it's `SK` to `VERSION=yyyy-mm-ddThh:mm:ss+zz:zz`
      #    - Saving the new `VERSION=yyyy-mm-ddThh:mm:ss+zz:zz` item
      #    - Splicing in the current changes onto the existing `VERSION#latest` item
      #    - Returning the spliced `VERSION#latest` back to this method
      def new_version(provenance:, p_key:, client: nil, dmp:, latest_version: {})
        return nil unless p_key.is_a?(String) && !p_key.strip.empty? && _versionable?(dmp: dmp)

        client = Uc3DmpDynamo::Client.new(debug: debug) if client.nil?
        latest_version = Finder.by_p_key(client: client, p_key: p_key) unless latest_version.is_a?(Hash) &&
                                                                              !latest_version['PK'].nil?

        # Only continue if there was an existing record and its the latest version
        return nil unless latest['SK'] != Helper::DMP_LATEST_VERSION

        owner = latest['dmphub_provenance_id']
        updater = provenance['PK']
        prior = _generate_version(client: client, latest_version: latest, owner: owner, updater: updater)
        return nil if prior.nil?

        args = { owner: owner, updater: updater, base: prior, mods: dmp, debug: debug }
        puts 'DMP ID update prior to splicing changes' if debug
        puts dmp

        args = { owner: owner, updater: updater, base: prior, mods: dmp, debug: debug }
        # If the system of provenance is making the change then just use the
        # new version as the base and then splice in any mods made by others
        # args = args.merge({ base: new_version, mods: original_version })
        new_version = Splicer.splice_for_owner(args) if owner == updater
        # Otherwise use the original version as the base and then update the
        # metadata owned by the updater system
        new_version = Splicer.splice_for_others(args) if new_version.nil?
        new_version
      end

      # Build the :dmphub_versions array and attach it to the DMP JSON
      # rubocop:disable Metrics/AbcSize
      def append_versions(p_key:, dmp:, client: nil, debug: false)
        json = Helper.parse_json(json: dmp)
        return json unless p_key.is_a?(String) && !p_key.strip.empty? && json.is_a?(Hash) && !json['dmp'].nil?

        results = get_versions(p_key: p_key, client: client, debug: debug)
        return json unless results.length > 1

        versions = results.map do |ver|
          next if ver['modified'].nil?
          {
            timestamp: ver['modified'],
            url: "#{Helper.api_base_url}dmps/#{Helper.remove_pk_prefix(p_key: p_key)}?version=#{ver['modified']}"
          }
        end
        json['dmp']['dmphub_versions'] = JSON.parse(versions.to_json)
        json
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Determine whether the specified DMP metadata is versionable - returns boolean
      def _versionable?(dmp:)
        return false unless dmp.is_a?(Hash) && dmp['PK'].nil? && dmp['SK'].nil?

        # It's versionable if it has a DMP ID
        !dmp.fetch('dmp_id', {})['identifier'].nil?
      end

      # Generate a version
      # rubocop:disable Metrics/AbcSize,  Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
      def _generate_version(client:, latest_version:, owner:, updater:, debug: false)
        # Only create a version if the Updater is not the Owner OR the changes have happened on a different day
        mod_time = Time.parse(latest_version.fetch('dmphub_updated_at', Time.now.iso8601))
        now = Time.now
        return latest_version if mod_time.nil? || !(now - mod_time).is_a?(Float)

        same_hour = (now - mod_time).round <= 3600
        return latest_version if owner != updater || (owner == updater && same_hour)

        latest_version['SK'] = "#{Helper::SK_DMP_PREFIX}#{latest_version['dmphub_updated_at'] || Time.now.iso8601}"

        # Create the prior version record
        resp = client.put_item(json: latest_version, debug: debug)
        return nil if resp.nil?

        puts "Created new version #{latest_version['PK']} - #{latest_version['SK']}" if debug
        latest_version
      end
      # rubocop:enable Metrics/AbcSize,  Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
    end
  end
end
