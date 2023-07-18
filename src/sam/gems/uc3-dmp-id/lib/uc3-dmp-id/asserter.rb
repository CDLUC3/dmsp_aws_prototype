# frozen_string_literal: true

module Uc3DmpId
  class AsserterError < StandardError; end

  class Asserter
    class << self
      # Add assertions to a DMP ID - this is performed by non-provenance systems
      def add(updater:, dmp:, mods:, note: nil, logger: nil)

puts "ADDING ASSERTIONS: #{mods}"

        # If the updater and provenance are the same just return the :dmp as-is
        return dmp if updater.nil? || !dmp.is_a?(Hash) || !mods.is_a?(Hash) ||
                      updater&.gsub('PROVENANCE#', '') == dmp['dmphub_provenance_id']&.gsub('PROVENANCE#', '')

        contact = mods['contact']
        contributor = mods.fetch('contributor', [])
        project = mods.fetch('project', [])
        # Return the DMP ID as-is if there are no assertable changes
        return dmp if contact.nil? && contributor.empty? && project.empty?

        # Clone any existing assertions on the current DMP ID so we can manipulate them
        assertions = Helper.deep_copy_dmp(obj: dmp.fetch('dmphub_assertions', []))
        # Return the DMP ID as-is if the assertion is already on the record
        return dmp if assertions.select { |entry| entry['provenance'] == updater && entry['assertions'] == mods }

        assertions << _generate_assertion(updater: updater, mods: mods, note: note)
        dmp['dmphub_assertions'] = assertions.flatten
        dmp
      end

      # Splice together assertions made while the user was updating the DMP ID
      def splice(latest_version:, modified_version:, logger: nil)

puts "LATEST_VERSION ASSERTIONS: #{latest_version['dmphub_assertions']}"
puts "MODIFIED_VERSION ASSERTIONS: #{modified_version['dmphub_assertions']}"

        # Return the modified_version if the timestamps are the same (meaning no new assertions were made while the
        # user was working on the DMP ID) OR neither version has assertions
        return modified_version if latest_version['dmphub_updated_at'] == modified_version['dmphub_updated_at'] ||
                                   (latest_version.fetch('dmphub_assertions', []).empty? &&
                                    modified_version.fetch('dmphub_assertions', []).empty?)

        # Clone any existing assertions on the current DMP ID so we can manipulate them
        existing_assertions = Helper.deep_copy_dmp(obj: latest_version.fetch('dmphub_assertions', []))
        incoming_assertions = Helper.deep_copy_dmp(obj: modified_version.fetch('dmphub_assertions', []))
        logger.debug(message: "Existing assertions", details: existing_assertions) if logger.respond_to?(:debug)
        logger.debug(message: "Incoming modifications", details: incoming_assertions) if logger.respond_to?(:debug)

        # Keep any assetions that were made after the dmphub_updated_at on the incoming changes
        modified_version['dmphub_assertions'] = existing_assertions.select do |entry|
          !entry['timestamp'].nil? && Time.parse(entry['timestamp']) > Time.parse(modified_version['dmphub_updated_at'])
        end
        return modified_version unless incoming_assertions.any?

        # Add any of the assertions still on the incoming record back to the latest record
        incoming_assertions.each { |entry| modified_version['dmphub_assertions'] << entry }
        modified_version
      end

      private

      # Generate an assertion entry. For example:
      #
      # {
      #    "id": "ABCD1234",
      #    "provenance": "dmphub",
      #    "timestamp": "2023-07-07T14:50:23+00:00",
      #    "note": "data received from the NIH API",
      #    "assertions": {
      #      "contact": {
      #        "name": "Wrong Person"
      #      },
      #      "contributor": [
      #        {
      #          "name": "Jane Doe",
      #          "role": ["Investigation"]
      #        }
      #      ],
      #      "project": [
      #        {
      #          "start": "2024-01-01T00:00:00+07:00",
      #          "end": "2025-12-31T23:59:59+07:00"
      #        }
      #      ],
      #      "funding": [
      #        {
      #          "funder_id": {
      #            "identifier": "https://doi.org/10.13039/501100001807",
      #            "type": "fundref"
      #          },
      #          "funding_status": "granted",
      #          "grant_id": {
      #            "identifier": "2019/22702-3",
      #            "type": "other"
      #          }
      #        }
      #      ]
      #    }
      # }
      def _generate_assertion(updater:, mods:, note: '')
        return nil if updater.nil? || !mod.is_a?(Hash)

        JSON.parse({
          id: SecureRandom.hex(4).upcase,
          provenance: updater.gsub('PROVENANCE#', ''),
          timestamp: Time.now.iso8601,
          status: 'new',
          note: note,
          assertions: mods
        }.to_json)
      end
    end
  end
end
