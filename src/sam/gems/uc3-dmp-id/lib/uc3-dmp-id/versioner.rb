# frozen_string_literal: true

require 'uc3-dmp-dynamo'
require 'time'

module Uc3DmpId
  class VersionerError < StandardError; end

  # Logic to handle the versioning of DMP IDs and to retrieve the versions for a PK
  class Versioner
    SOURCE = 'Uc3DmpId::Versioner'

    class << self
      # Find the DMP ID's versions
      # -------------------------------------------------------------------------
      def get_versions(p_key:, client: nil, logger: nil)
        return [] unless p_key.is_a?(String) && !p_key.strip.empty?

        args = {
          key_conditions: {
            PK: { attribute_value_list: [Helper.append_pk_prefix(p_key:)], comparison_operator: 'EQ' }
          },
          projection_expression: 'modified',
          scan_index_forward: false
        }
        client = Uc3DmpDynamo::Client.new if client.nil?
        client.query(args:, logger:)
      end

      # Generate a snapshot of the current latest version of the DMP ID using the existing :modified as
      # the new SK.
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength,
      # rubocop:disable Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
      def generate_version(client:, latest_version:, owner:, updater:, logger: nil)
        # Only create a version if the Updater is not the Owner OR the changes have happened on a different day
        mod_time = Time.parse(latest_version.fetch('modified', Time.now.utc.iso8601))
        now = Time.now.utc
        if mod_time.nil? || !(now - mod_time).is_a?(Float)
          logger.error(message: "#{SOURCE} unable to determine mod time: #{mod_time}") if logger.respond_to?(:debug)
          return latest_version
        end

        # Only allow a new version if the owner and updater are the same and it has been at least one hour since
        # the last version was created
        same_hour = (now - mod_time).round <= 3600
        if owner == updater && same_hour
          logger.debug(message: "#{SOURCE} same owner and updater? #{owner == updater}") if logger.respond_to?(:debug)
          if logger.respond_to?(:debug)
            logger.debug(message: "#{SOURCE} already updated within the past hour? #{same_hour}")
          end
          return latest_version
        end

        # Make a copy of the latest_version and then update it's SK to the :modified to mark it in a point of time
        # We essentially make a snapshot of the record before making changes
        prior = Helper.deep_copy_dmp(obj: latest_version)
        prior['SK'] = "#{Helper::SK_DMP_PREFIX}#{latest_version['modified'] || Time.now.utc.iso8601}"

        # Create the prior version record ()
        client = Uc3DmpDynamo::Client.new if client.nil?
        prior['dmphub_modifications'] = []
        resp = client.put_item(json: prior, logger:)
        return nil if resp.nil?

        msg = "#{SOURCE} created version PK: #{prior['PK']} SK: #{prior['SK']}"
        logger.info(message: msg, details: prior) if logger.respond_to?(:debug)
        latest_version
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength,
      # rubocop:enable Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity

      # Build the :dmphub_versions array and attach it to the DMP JSON
      # rubocop:disable Metrics/AbcSize
      def append_versions(p_key:, dmp:, client: nil, logger: nil)
        json = Helper.parse_json(json: dmp)
        return json unless p_key.is_a?(String) && !p_key.strip.empty? && json.is_a?(Hash) && !json['dmp'].nil?

        results = get_versions(p_key:, client:, logger:)
        return json unless results.length > 1

        # TODO: we may want to include milliseconds in the future if we get increased volume so that
        #       we don't end up with duplicate URLs if versions are made within the same second
        versions = results.map do |ver|
          next if ver['modified'].nil?

          base_url = "#{Helper.landing_page_url}#{Helper.remove_pk_prefix(p_key:)}"
          {
            timestamp: ver['modified'],
            url: dmp['dmp']['modified'] == ver['modified'] ? base_url : "#{base_url}?version=#{ver['modified']}"
          }
        end
        json['dmp']['dmphub_versions'] = JSON.parse(versions.to_json)
        json
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
