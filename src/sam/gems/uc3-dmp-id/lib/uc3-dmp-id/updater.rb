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
      def update(provenance:, p_key:, json: {}, note: nil, logger: nil)
        raise UpdaterError, Helper::MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        mods = Helper.parse_json(json:).fetch('dmp', {})
        p_key = Helper.append_pk_prefix(p_key:)
        logger.debug(message: "Incoming modifications for PK #{p_key}", details: mods) if logger.respond_to?(:debug)

        # Fetch the latest version of the DMP ID
        client = Uc3DmpDynamo::Client.new
        latest_version = Finder.by_pk(p_key:, client:, logger:, cleanse: false)
        latest_version = latest_version.fetch('dmp', {}) unless latest_version['dmp'].nil?
        logger.debug(message: "Latest version for PK #{p_key}", details: latest_version) if logger.respond_to?(:debug)

        # Verify that the DMP ID is updateable with the info passed in
        errs = _updateable?(provenance:, p_key:, latest_version: latest_version['dmp'],
                            mods: mods['dmp'])
        logger.error(message: errs.join(', ')) if logger.respond_to?(:error) && errs.is_a?(Array) && errs.any?
        raise UpdaterError, errs if errs.is_a?(Array) && errs.any?
        # Don't continue if nothing has changed!
        raise UpdaterError, Helper::MSG_NO_CHANGE if Helper.eql?(dmp_a: latest_version, dmp_b: mods)

        # Version the DMP ID record (if applicable).
        owner = latest_version['dmphub_provenance_id']
        updater = provenance['PK']
        version = Versioner.generate_version(client:, latest_version:, owner:,
                                             updater:, logger:)
        raise UpdaterError, Helper::MSG_DMP_UNABLE_TO_VERSION if version.nil?
        # Bail if the system trying to make the update is not the creator of the DMP ID
        raise UpdaterError, Helper::MSG_DMP_FORBIDDEN if owner != updater

        # Remove the version info because we don't want to save it on the record
        version.delete('dmphub_versions')

        # Splice the assertions
        version = _process_modifications(owner:, updater:, version:, mods:, note:,
                                         logger:)
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
        json = JSON.parse({ dmp: version }.to_json)
        json = Versioner.append_versions(p_key:, dmp: json, client:, logger:)
        Helper.cleanse_dmp_json(json:)
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
        dmp = Finder.by_pk(p_key:, client:, logger:, cleanse: false)
        logger.info(message: 'Existing latest record', details: dmp) if logger.respond_to?(:debug)
        raise UpdaterError, Helper::MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil? &&
                                                             provenance['PK'] == dmp['dmp']['dmphub_provenance_id']

        # Add the download URl for the PDF as a related identifier on the DMP ID record
        annotated = Helper.annotate_dmp_json(provenance:, p_key:, json: dmp['dmp'])
        annotated['dmproadmap_related_identifiers'] = [] if annotated['dmproadmap_related_identifiers'].nil?
        annotated['dmproadmap_related_identifiers'] << JSON.parse({
          descriptor: 'is_metadata_for', work_type: 'output_management_plan', type: 'url', identifier: url
        }.to_json)

        # Save the changes without creating a new version!
        resp = client.put_item(json: annotated, logger:)
        raise UpdaterError, Helper::MSG_DMP_UNABLE_TO_VERSION if resp.nil?

        logger.info(message: "Added DMP ID narrative for PK: #{p_key}, Narrative: #{url}") if logger.respond_to?(:debug)
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

      # rubocop:disable Metrics/ParameterLists
      def _process_modifications(owner:, updater:, version:, mods:, note: nil, logger: nil)
        return version unless mods.is_a?(Hash) && !updater.nil?
        return mods unless version.is_a?(Hash) && !owner.nil?

        logger.debug(message: 'Modifications before merge.', details: mods) if logger.respond_to?(:debug)
        keys_to_retain = version.keys.select do |key|
          (key.start_with?('dmphub_') && !%w[dmphub_modifications dmphub_versions].include?(key)) ||
            key.start_with?('PK') || key.start_with?('SK')
        end
        keys_to_retain.each do |key|
          mods[key] = version[key]
        end
        logger.debug(message: 'Modifications after merge.', details: mods) if logger.respond_to?(:debug)
        mods
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
    end
  end
end
