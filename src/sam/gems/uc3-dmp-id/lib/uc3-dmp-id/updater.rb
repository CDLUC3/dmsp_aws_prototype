# frozen_string_literal: true

require 'securerandom'
require 'time'

module Uc3DmpId
  class UpdaterError < StandardError; end

  class Updater
    class << self
      # Update a DMP ID
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # -------------------------------------------------------------------------
      def update(provenance:, p_key:, json: {}, note: nil, logger: nil)
        raise UpdaterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        mods = Helper.parse_json(json: json).fetch('dmp', {})
        p_key = Helper.append_pk_prefix(p_key: p_key)
        logger.debug(message: "Incoming modifications for PK #{p_key}", details: mods) if logger.respond_to?(:debug)

        # Fetch the latest version of the DMP ID
        client = Uc3DmpDynamo::Client.new
        latest_version = Finder.by_pk(p_key: p_key, client: client, logger: logger, cleanse: false)
        latest_version = latest_version['dmp'].nil? ? latest_version : latest_version.fetch('dmp', {})
        logger.debug(message: "Latest version for PK #{p_key}", details: latest_version) if logger.respond_to?(:debug)

        # Verify that the DMP ID is updateable with the info passed in
        errs = _updateable?(provenance: provenance, p_key: p_key, latest_version: latest_version['dmp'], mods: mods['dmp'])
        logger.error(message: errs.join(', ')) if errs.is_a?(Array) && errs.any?
        raise UpdaterError, errs if errs.is_a?(Array) && errs.any?
        # Don't continue if nothing has changed!
        raise UpdaterError, MSG_NO_CHANGE if Helper.eql?(dmp_a: latest_version, dmp_b: mods)

        # Version the DMP ID record (if applicable).
        owner = latest_version['dmphub_provenance_id']
        updater = provenance['PK']
        version = Versioner.generate_version(client: client, latest_version: latest_version, owner: owner, updater: updater,
                                             logger: logger)
        raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if version.nil?

        # Splice the assertions
        version = _process_modifications(owner: owner, updater: updater, version: version, mods: mods, note: note,
                                         logger: logger)

        # Set the :modified timestamps
        now = Time.now.utc.iso8601
        version['modified'] = now

        # Save the changes
        resp = client.put_item(json: version, logger: logger)
        raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if resp.nil?

        # Send the updates to EZID
        _post_process(provenance: provenance, json: version, logger: logger)

        # Return the new version record
        logger.info(message: "Updated DMP ID: #{p_key}") if logger.respond_to?(:debug)
        Helper.cleanse_dmp_json(json: JSON.parse({ dmp: version }.to_json))
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Save a DMP ID's corresponding narrative PDF document to S3 and add the download URL for that
      # document to the DMP ID's :dmpraodmap_related_identifiers array as an `is_metadata_for` relation
      def attach_narrative(provenance:, p_key:, url:, logger: nil)
        raise UpdaterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        # fetch the existing latest version of the DMP ID
        client = Uc3DmpDynamo::Client.new(logger: logger)
        dmp = Finder.by_pk(p_key: p_key, client: client, logger: logger, cleanse: false)
        logger.info(message: "Existing latest record", details: dmp) if logger.respond_to?(:debug)
        raise UpdaterError, MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil? &&
                                                     provenance['Pk'] == dmp['dmphub_provenance_id']

        # Add the download URl for the PDF as a related identifier on the DMP ID record
        annotated = Helper.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp['dmp'])
        annotated['dmproadmap_related_identifiers'] = [] if annotated['dmproadmap_related_identifiers'].nil?
        annotated['dmproadmap_related_identifiers'] << {
          descriptor: 'is_metadata_for', work_type: 'output_management_plan', type: 'url', identifier: url
        }

        # Save the changes without creating a new version!
        resp = client.put_item(json: annotated, logger: logger)
        raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if resp.nil?

        logger.info(message: "Added DMP ID narrative for PK: #{p_key}, Narrative: #{url}") if logger.respond_to?(:debug)
        true
      end

      private

      # Check to make sure the incoming JSON is valid, the DMP ID requested matches the DMP ID in the JSON
      def _updateable?(provenance:, p_key:, latest_version: {}, mods: {})
        # Validate the incoming JSON first
        errs = Validator.validate(mode: 'author', json: JSON.parse({ dmp: mods }.to_json))
        return errs.join(', ') if errs.is_a?(Array) && errs.any? && errs.first != Validator::MSG_VALID_JSON
        # Fail if the provenance is not defined
        return [MSG_DMP_FORBIDDEN] unless provenance.is_a?(Hash) && !provenance['PK'].nil?
        # Verify that the JSON is for the same DMP in the PK
        return [MSG_DMP_FORBIDDEN] unless Helper.dmp_id_to_pk(json: mods.fetch('dmp_id', {})) == p_key
        # Bail out if the DMP ID could not be found or the PKs do not match for some reason
        return [MSG_DMP_UNKNOWN] if latest_version.nil? || latest_version.fetch['PK'] != p_key
      end

      def _process_modifications(owner:, updater:, version:, mods:, note: nil, logger: nil)
        return version unless mods.is_a?(Hash) && !updater.nil?
        return mods unless version.is_a?(Hash) && !owner.nil?

        # Splice together any assertions that may have been made while the user was editing the DMP ID
        updated = Asserter.splice(latest_version: version, modified_version: mods, logger: logger) if owner == updater

        # Attach the incoming changes as an assertion to the DMP ID since the updater is NOT the owner
        updated = Asserter.add(updater: updater, dmp: version, mods: mods, note: note, logger: logger) if owner != updater

        merge_versions(latest_version: version, mods: updated, logger: logger)
      end

      # We are replacing the latest version with the modifcations but want to retain the PK, SK and any dmphub_ prefixed
      # entries in the metadata so that we do not lose creation timestamps, provenance ids, etc.
      def merge_versions(latest_version:, mods:, logger: nil)
        logger.debug(message: 'Modifications before merge.', details: mods)
        keys_to_retain = latest_version.keys.select do |key|
          (key.start_with?('dmphub_') && !%w[dmphub_assertions].include?(key)) ||
            key.start_with?('PK') || key.start_with?('SK')
        end
        keys_to_retain.each do |key|
          mods[key] = latest_version[key]
        end
        logger.debug(message: 'Modifications after merge.', details: mods)
        mods
      end

      # Once the DMP has been updated, we need to update it's DOI metadata
      # -------------------------------------------------------------------------
      def _post_process(provenance:, json:, logger: nil)
        return false unless json.is_a?(Hash)

        # Indicate whether or not the updater is the provenance system
        json['dmphub_updater_is_provenance'] = provenance['PK'] == json['dmphub_provenance_id']
        # Publish the change to the EventBridge
        publisher = Uc3DmpEventBridge::Publisher.new
        publisher.publish(source: 'DmpUpdater', dmp: json, logger: logger)
        true
      end
    end
  end
end
