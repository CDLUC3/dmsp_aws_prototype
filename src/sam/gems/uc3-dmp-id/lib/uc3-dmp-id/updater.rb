# frozen_string_literal: true

require 'securerandom'
require 'time'

module Uc3DmpId
  class UpdaterError < StandardError; end

  # Class that handles updating a DMP ID
  class Updater
    class << self
      # Update a DMP ID
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # -------------------------------------------------------------------------
      def update(provenance:, p_key:, json: {}, logger: nil)
        raise UpdaterError, Helper::MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        payload = Helper.parse_json(json:).fetch('dmp', {})
        p_key = Helper.append_pk_prefix(p_key:)
        logger.debug(message: "Incoming modifications for PK #{p_key}", details: payload) if logger.respond_to?(:debug)

        # Fetch the latest version of the DMP ID
        client = Uc3DmpDynamo::Client.new
        latest_version = Finder.by_pk(p_key:, client:, logger:, cleanse: false)
        latest_version = latest_version.fetch('dmp', {}) unless latest_version['dmp'].nil?
        logger.debug(message: "Latest version for PK #{p_key}", details: latest_version) if logger.respond_to?(:debug)

        # Verify that the DMP ID is updateable with the info passed in
        errs = _updateable?(provenance:, p_key:, latest_version: latest_version['dmp'],
                            mods: payload['dmp'])
        logger.error(message: errs.join(', ')) if logger.respond_to?(:error) && errs.is_a?(Array) && errs.any?
        raise UpdaterError, errs if errs.is_a?(Array) && errs.any?
        # Don't continue if nothing has changed!
        raise UpdaterError, Helper::MSG_NO_CHANGE if Helper.eql?(dmp_a: latest_version, dmp_b: payload)

        # Version the DMP ID record (if applicable).
        owner = latest_version['dmphub_provenance_id']
        updater = provenance['PK']
        version = Versioner.generate_version(client:, latest_version:, owner:,
                                             updater:, logger:)
        logger&.debug(message: 'New Version', details: version)
        raise UpdaterError, Helper::MSG_DMP_UNABLE_TO_VERSION if version.nil?
        # Bail if the system trying to make the update is not the creator of the DMP ID
        raise UpdaterError, Helper::MSG_DMP_FORBIDDEN if owner != updater

        # Handle any changes to the dmphub_modifications section
        version = _process_harvester_mods(client:, p_key:, json: payload, version:, logger:)
        logger&.debug(message: 'Version after process_harvester_mods', details: version)
        raise UpdaterError, Helper::MSG_SERVER_ERROR if version.nil?

        # Remove the version info any any lingering modification blocks
        version.delete('dmphub_versions')
        version.delete('dmphub_modifications')

        # Set the :modified timestamps
        now = Time.now.utc
        version['modified'] = now.iso8601
        version['dmphub_modification_day'] = now.strftime('%Y-%m-%d')

        # Save the changes
        resp = client.put_item(json: version, logger:)
        raise UpdaterError, Helper::MSG_DMP_UNABLE_TO_VERSION if resp.nil?

        # Send the updates to EZID
        _post_process(provenance:, json: version, logger:)

        # Return the new version record
        logger.info(message: "Updated DMP ID: #{p_key}") if logger.respond_to?(:debug)

        # Append the :dmphub_versions Array
        out = JSON.parse({ dmp: version }.to_json)
        out = Versioner.append_versions(p_key:, dmp: out, client:, logger:)
        Helper.cleanse_dmp_json(json: out)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Save a DMP ID's corresponding narrative PDF document to S3 and add the download URL for that
      # document to the DMP ID's :dmpraodmap_related_identifiers array as an `is_metadata_for` relation
      # rubocop:disable Metrics/AbcSize
      def attach_narrative(provenance:, p_key:, url:, logger: nil)
        raise UpdaterError, Helper::MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        # fetch the existing latest version of the DMP ID
        client = Uc3DmpDynamo::Client.new(logger:)
        # dmp = Finder.by_pk(p_key:, client:, logger:, cleanse: false)
        resp = client.get_item(
          key: { PK: Helper.append_pk_prefix(p_key:), SK: Helper::DMP_LATEST_VERSION },
          logger:
        )
        raise UpdaterError, Helper::MSG_DMP_INVALID_DMP_ID unless resp.is_a?(Hash)

        dmp = resp['dmp'].nil? ? resp : resp['dmp']
        logger.info(message: 'Existing latest record', details: dmp) if logger.respond_to?(:debug)
        raise UpdaterError, Helper::MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil? &&
                                                             provenance['PK'] == dmp['dmphub_provenance_id']

        logger&.debug(message: "DMP Prior to narrative attachment", details: dmp)

        # Add the download URl for the PDF as a related identifier on the DMP ID record
        dmp['dmproadmap_related_identifiers'] = [] if dmp['dmproadmap_related_identifiers'].nil?
        dmp['dmproadmap_related_identifiers'] << JSON.parse({
          descriptor: 'is_metadata_for', work_type: 'output_management_plan', type: 'url', identifier: url
        }.to_json)

        # Save the changes without creating a new version!
        logger&.debug(message: "DMP After narrative attachment", details: dmp)
        resp = client.put_item(json: dmp, logger:)
        raise UpdaterError, Helper::MSG_DMP_UNABLE_TO_VERSION if resp.nil?

        logger&.debug(message: "Added DMP ID narrative for PK: #{p_key}, Narrative: #{url}")
        true
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Check to make sure the incoming JSON is valid, the DMP ID requested matches the DMP ID in the JSON
      # rubocop:disable Metrics/AbcSize
      def _updateable?(provenance:, p_key:, latest_version: {}, mods: {})
        # Validate the incoming JSON first
        errs = Validator.validate(mode: 'author', json: JSON.parse({ dmp: mods }.to_json))
        return errs.join(', ') if errs.is_a?(Array) && errs.any? && errs.first != Validator::MSG_VALID_JSON
        # Fail if the provenance is not defined
        return [Helper::MSG_DMP_FORBIDDEN] unless provenance.is_a?(Hash) && !provenance['PK'].nil?
        # Verify that the JSON is for the same DMP in the PK
        return [Helper::MSG_DMP_FORBIDDEN] unless Helper.dmp_id_to_pk(json: mods.fetch('dmp_id', {})) == p_key

        # Bail out if the DMP ID could not be found or the PKs do not match for some reason
        [Helper::MSG_DMP_UNKNOWN] unless latest_version.is_a?(Hash) && latest_version['PK'] == p_key
      end
      # rubocop:enable Metrics/AbcSize

      # Once the DMP has been updated, we need to update it's DOI metadata
      # -------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      def _post_process(provenance:, json:, logger: nil)
        return false unless json.is_a?(Hash) && provenance.is_a?(Hash) && !provenance['PK'].nil? &&
                            !json['dmphub_provenance_id'].nil?

        publishable = provenance['PK'] == json['dmphub_provenance_id']
        return true unless publishable

        # TODO: we will want to send and related_identifiers in :dmphub_modifications as well!!!

        publisher = Uc3DmpEventBridge::Publisher.new
        # Publish the change to the EventBridge if the updater is the owner of the DMP ID
        if publishable && logger.respond_to?(:debug)
          logger.debug(message: 'Sending event for EZID publication',
                       details: json)
        end
        publisher.publish(source: 'DmpUpdater', event_type: 'EZID update', dmp: json, logger:) if publishable

        # Determine if there are any related identifiers that we should try to fetch a citation for
        citable_identifiers = Helper.citable_related_identifiers(dmp: json)
        return true if citable_identifiers.empty?

        # Process citations
        citer_detail = {
          PK: json['PK'],
          SK: json['SK'],
          dmproadmap_related_identifiers: citable_identifiers
        }
        if logger.respond_to?(:debug)
          logger.debug(message: 'Sending event to fetch citations',
                       details: citable_identifiers)
        end
        publisher.publish(source: 'DmpUpdater', dmp: json, event_type: 'Citation Fetch', detail: citer_detail,
                          logger:)
        true
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

      # Fetch any Harvester modifications to the JSON
      def _process_harvester_mods(client:, p_key:, json:, version:, logger: nil)
        logger&.debug(message: 'Incoming modifications', details: json)
        return version if json.fetch('dmphub_modifications', []).empty?

        # Fetch the `"SK": "HARVESTER_MODS"` record
        client = Uc3DmpDynamo::Client.new if client.nil?
        resp = client.get_item(
          key: { PK: Helper.append_pk_prefix(p_key:), SK: Helper::SK_HARVESTER_MODS }, logger:
        )
        return version unless resp.is_a?(Hash) && resp['related_works'].is_a?(Hash)

        logger&.debug(message: 'Original HARVESTER_MODS record', details: resp)
        # The `dmphub_modifications` array will ONLY ever have things the harvester mods know about
        # so just find them and update the status accordingly
        original = resp.dup
        json['dmproadmap_related_identifiers'] = [] if json['dmproadmap_related_identifiers'].nil?

        json['dmphub_modifications'].each do |entry|
          next if entry.is_a?(Hash) && entry.fetch('dmproadmap_related_identifiers', []).empty?

          entry['dmproadmap_related_identifiers'].each do |related|
            # Detrmine if the HARVESTER_MODS record even knows about the mod
            related_id = related.respond_to?(:identifier) ? related.identifier : related['identifier']
            related_domain = related.respond_to?(:domain) ? related.domain : related['domain']
            key = "#{related_domain.end_with?('/') ? related_domain : "#{related_domain}/"}#{related_id}"
            key_found = original['related_works'].has_key?(key)
            logger&.debug(message: "No matching HARVEST_MOD found for #{key}") unless key_found
            next unless key_found

            # Update the status in the HARVESTER_MODS record
            logger&.debug(message: "Updating status for #{key} from #{original['related_works'][key]['status']} to #{related['status']}")
            original['related_works'][key]['status'] = related['status']

            existing = version['dmproadmap_related_identifiers'].select do |ri|
              ri['identifier'] == key
            end

            # Add it if it was approved and doesn't exist in dmproadmap_related_identifiers
            if related['status'] == 'approved' && existing.empty?
              version['dmproadmap_related_identifiers'] << JSON.parse({
                identifier: key,
                work_type: related['work_type'],
                type: related['type'],
                descriptor: related['descriptor'],
                citation: related['citation']
              }.to_json)
            elsif related['status'] == 'rejected' && existing.any?
              # otherwise remove it
              version['dmproadmap_related_identifiers'] = version['dmproadmap_related_identifiers'].reject { |ri| ri == existing.first }
            end
          end
        end

        logger&.debug(message: 'Updating HARVESTER_MODS with:', details: original)
        resp = client.put_item(json: original, logger:)
        logger&.error(message: 'Unable to update HARVESTER_MODS', details: original) if resp.nil?

        logger&.debug(message: 'Returning updated VERSION:', details: version)
        version
      end
    end
  end
end
