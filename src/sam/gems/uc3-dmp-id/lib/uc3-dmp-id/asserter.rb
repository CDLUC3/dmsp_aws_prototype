# frozen_string_literal: true

require 'time'

module Uc3DmpId
  class AsserterError < StandardError; end

  # Class that handles changes to a DMP ID's :dmphub_modifications section
  class Asserter
    DEFAULT_DESCRIPTOR = 'references'
    DEFAULT_WORK_TYPE = 'other'

    class << self
      # Add assertions to a DMP ID - this is performed by non-provenance systems
      # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      def add(updater:, latest_version:, modified_version:, note: nil, logger: nil)
        return latest_version unless latest_version.is_a?(Hash)

        owner = latest_version['dmphub_provenance_id']&.gsub('PROVENANCE#', '')
        # If the updater and provenance are the same just return the :dmp as-is
        return latest_version if updater.nil? || !latest_version.is_a?(Hash) || !modified_version.is_a?(Hash) ||
                                 updater&.gsub('PROVENANCE#', '') == owner

        # contact = modified_version['contact']
        # contributor = modified_version.fetch('contributor', [])
        # project = modified_version.fetch('project', [])
        funding = modified_version.fetch('project', []).first&.fetch('funding', [])
        related_works = modified_version.fetch('dmproadmap_related_identifiers', [])

        if related_works.any?
          latest_version = _add_related_identifier(updater:, latest_version:,
                                                   identifiers: related_works, note:, logger:)
        end
        return latest_version unless !funding.nil? && funding.any?

        _add_funding_mod(updater:, latest_version:, funding:,
                         note:, logger:)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

      # Splice together assertions made by the owner of the DMP ID so that any :dmphub_modifications made to
      # the record while it was being updated are not lost
      # rubocop:disable Metrics/AbcSize
      def splice(latest_version:, modified_version:, logger: nil)
        # Return the modified_version if the timestamps are the same OR neither version has :dmphub_modifications
        return modified_version if latest_version['modified'] == modified_version['modified'] ||
                                   (latest_version.fetch('dmphub_modifications', []).empty? &&
                                    modified_version.fetch('dmphub_modifications', []).empty?)

        # Clone any existing :dmphub_modifications on the current DMP ID so we can retain them
        existing_assertions = Helper.deep_copy_dmp(obj: latest_version.fetch('dmphub_modifications', []))
        incoming_assertions = Helper.deep_copy_dmp(obj: modified_version.fetch('dmphub_modifications', []))
        if logger.respond_to?(:debug)
          logger.debug(message: 'Existing dmphub_modifications',
                       details: existing_assertions)
        end
        if logger.respond_to?(:debug)
          logger.debug(message: 'Incoming dmphub_modifications',
                       details: incoming_assertions)
        end

        # Keep any :dmphub_modifications and then add the incoming to the Array
        modified_version['dmphub_modifications'] = existing_assertions
        return modified_version unless incoming_assertions.any?

        # Add any of the assertions still on the incoming record back to the latest record
        incoming_assertions.each { |entry| modified_version['dmphub_modifications'] << entry }
        modified_version
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Verify that the DMP ID record does not already have the specified identifiers and then add them
      # to the :latest_version in the :dmphub_modifications Array
      #
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      def _add_related_identifier(updater:, latest_version:, identifiers:, note: '', logger: nil)
        return latest_version unless updater.is_a?(String) && latest_version.is_a?(Hash) && identifiers.is_a?(Array)

        latest_version['dmphub_modifications'] = [] if latest_version['dmphub_modifications'].nil?
        known_mods = latest_version['dmphub_modifications'].map do |mod|
          mod.fetch('dmproadmap_related_identifiers', [])
        end
        known_mods = known_mods.flatten.compact.map { |mod| mod['identifier'].downcase.strip }.compact.uniq

        asserted = latest_version.fetch('dmproadmap_related_identifiers', [])
        asserted = asserted.flatten.compact.map { |mod| mod['identifier'].downcase.strip }.compact.uniq

        additions = []
        identifiers.each do |related_identifier|
          # Skip if there is no :type or :identifier value
          if !related_identifier.is_a?(Hash) || related_identifier['type'].nil? || related_identifier['identifier'].nil?
            next
          end

          id = related_identifier['identifier'].downcase.strip
          # Skip if the :identifier is already listed in :dmphub_modifications or the
          # :dmproadmap_related_identifiers Arrays
          next if known_mods.include?(id) || asserted.include?(id)

          related_identifier['work_type'] = DEFAULT_WORK_TYPE if related_identifier['work_type'].nil?
          related_identifier['descriptor'] = DEFAULT_DESCRIPTOR if related_identifier['descriptor'].nil?
          additions << related_identifier
        end

        latest_version['dmproadmap_related_identifiers'] = [] if latest_version['dmproadmap_related_identifiers'].nil?
        assertion = _generate_assertion(updater:, note:,
                                        mods: JSON.parse({ dmproadmap_related_identifiers: additions }.to_json))
        if logger.respond_to?(:debug)
          logger.debug(message: 'Adding change to :dmphub_modifications.',
                       details: assertion)
        end
        latest_version['dmphub_modifications'] << assertion
        latest_version
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

      # Verify that the DMP ID record does not already have the specified funding change and then add it
      # to the :latest_version in the :dmphub_modifications Array
      #
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      def _add_funding_mod(updater:, latest_version:, funding:, note: '', logger: nil)
        return latest_version unless updater.is_a?(String) && latest_version.is_a?(Hash) && funding.is_a?(Array)

        known_mods = latest_version['dmphub_modifications'].map do |mod|
          next if mod.nil?

          mod.fetch('funding', {}).fetch('grant_id', {})['identifier']&.downcase&.strip
        end
        known_mods = known_mods.flatten.compact.uniq

        asserted = latest_version.fetch('project', [])&.map do |project|
          next if project.nil?

          project&.fetch('funding', [])&.first&.fetch('grant_id', {})&.[]('identifier')&.downcase&.strip
        end
        asserted = asserted.flatten.compact.uniq

        fund = funding.reject { |entry| entry['grant_id'].nil? }.first
        # Skip if there is no :grant_id
        return latest_version if !fund.is_a?(Hash) || fund.fetch('grant_id', {})['identifier'].nil?

        grant_id = fund.fetch('grant_id', {})['identifier'].downcase.strip
        # Skip if the :grant_id is already listed as a :dmphub_modifications or project: :funding
        return latest_version if known_mods.include?(grant_id) || asserted.include?(grant_id)

        latest_version['dmphub_modifications'] = [] if latest_version['dmphub_modifications'].nil?
        mod = JSON.parse({ funding: fund }.to_json)
        mod['funding']['funding_status'] = 'granted'
        assertion = _generate_assertion(updater:, mods: mod, note:)
        if logger.respond_to?(:debug)
          logger.debug(message: 'Adding change to :dmphub_modifications.',
                       details: assertion)
        end
        latest_version['dmphub_modifications'] << assertion
        latest_version
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

      # Generate an assertion entry. For example:
      #
      # {
      #    "id": "ABCD1234",
      #    "provenance": "dmphub",
      #    "timestamp": "2023-07-07T14:50:23+00:00",
      #    "note": "Data received from OpenAlex, matched by PI names and title keywords.",
      #    "confiedence": "Med",
      #    "dmproadmap_related_identifiers": {
      #      "work_type": "article",
      #      "descriptor": "is_cited_by",
      #      "type": "doi",
      #      "identifier": "https://dx.doi.org/99.9876/ZYX987.V6"
      #    }
      #  }
      #
      # OR:
      #
      #  {
      #    "id": "ABCD1234",
      #    "provenance": "dmphub",
      #    "timestamp": "2023-07-07T14:50:23+00:00",
      #    "note": "Data received from the NIH API, matched by the opportunity number.",
      #    "confidence": "High",
      #    "funding": {
      #      "funding_status": "granted",
      #      "grant_id": {
      #        "identifier": "2019/22702-3",
      #        "type": "other"
      #      }
      #    }
      #  }
      def _generate_assertion(updater:, mods:, note: '')
        return nil if updater.nil? || !mods.is_a?(Hash)

        assertion = {
          id: SecureRandom.hex(4).upcase,
          provenance: updater.gsub('PROVENANCE#', ''),
          timestamp: Time.now.utc.iso8601,
          status: 'pending',
          note:
        }
        mods.each_pair { |key, val| assertion[key] = val }
        JSON.parse(assertion.to_json)
      end
    end

    def _score_related_work(latest_version:, work:)

    end

    def _score_funding(latest_version:, funding:)

    end
  end
end
