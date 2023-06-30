# frozen_string_literal: true

module Uc3DmpId
  class UpdaterError < StandardError; end

  class Updater
    class << self
      # Update a record in the table
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # -------------------------------------------------------------------------
      def update(provenance:, p_key:, json: {})
      raise UpdaterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

      dmp = Helper.parse_json(json: json)
      errs = _updateable?(provenance: provenance, p_key: p_key, dmp: dmp)
      raise UpdaterError, errs if errs.is_a?(Array) && errs.any?

      # Add the DMPHub specific attributes
      annotated = Helper.annotate_dmp(provenance: provenance, json: dmp['dmp'], p_key: p_key)

      # fetch the existing latest version of the DMP ID
      client = Uc3DmpDynamo::Client.new(debug: debug)
      existing = Finder.by_pk(p_key: p_key, client: client, debug: debug)
      # Don't continue if nothing has changed!
      raise UpdaterError, MSG_NO_CHANGE if Helper.eql?(dmp_a: existing, dmp_b: annotated)

      # Generate a new version of the DMP. This involves versioning the current latest version
      new_version = versioner.new_version(p_key: p_key, dmp: json)
      raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if new_version.nil?

      # Save the changes as the new latest version
      resp = client.put_item(json: new_version, debug: debug)
      raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if resp.nil?

      # Send the updates to EZID, notify the provenance and download the PDF if applicable
      _post_process(json: dmp, debug: debug)
      resp
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def attach_narrative(provenance:, p_key:, url:, debug: false)
      raise UpdaterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

      # fetch the existing latest version of the DMP ID
      client = Uc3DmpDynamo::Client.new(debug: debug)
      dmp = Finder.by_pk(p_key: p_key, client: client, debug: debug)
      owner_org = Helper.extract_owner_org(json: dmp)
      # Don't continue if DMP ID could not be found or the contact has no identifier (should be impossible)
      raise UpdaterError, MSG_DMP_NOT_FOUND if dmp.nil? || owner_org.nil?

      errs = _updateable?(provenance: provenance, p_key: p_key, json: dmp['dmp'])
      raise UpdaterError, errs if errs.is_a?(Array) && errs.any?

      # Add the DMPHub specific attributes and then add the download URl for the PDF
      annotated = Helper.annotate_dmp_json(provenance: provenance, owner_org: owner_org, p_key: p_key, json: dmp['dmp'])
      annotated['dmproadmap_related_identifiers'] = [] if annotated['dmproadmap_related_identifiers'].nil?
      annotated['dmproadmap_related_identifiers'] << {
        descriptor: 'is_metadata_for', work_type: 'output_management_plan', type: 'url', identifier: url
      }

puts "Attached:"
puts annotated

      # Save the changes without creating a new version!
      resp = client.put_item(json: annotated, debug: debug)
      raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if resp.nil?

      true
    end

    private

    # Check if the DMP ID is updateable by the provenance
    def _updateable?(provenance:, p_key:, json:)
      # Validate the incoming JSON first
      errs = Validator.validate(mode: 'author', json: json)
      return errs.join(', ') if errs.is_a?(Array) && errs.any? && errs.first != Validator::MSG_VALID_JSON

      # Fail if the provenance is not defined
      return [MSG_DMP_FORBIDDEN] unless provenance.is_a?(Hash) && !provenance['PK'].nil?

      # Verify that the JSON is for the same DMP in the PK
      dmp_id = json.fetch('dmp_id', {})
      return [MSG_DMP_FORBIDDEN] unless Helper.dmp_id_to_pk(json: dmp_id) == p_key
      # Make sure they're not trying to update a historical copy of the DMP
      return [MSG_DMP_NO_HISTORICALS] if json['SK'] != Helper::DMP_LATEST_VERSION
    end

    # Once the DMP has been updated, we need to register it's DMP ID and download any PDF if applicable
    # -------------------------------------------------------------------------
    def _post_process(json:, debug: false)
      return false unless json.is_a?(Hash)

      # Indicate whether or not the updater is the provenance system
      json['dmphub_updater_is_provenance'] = @provenance['PK'] == json['dmphub_provenance_id']
      # Publish the change to the EventBridge
      publisher = Uc3DmpEventBridge::Publisher.new
      publisher.publish(source: 'DmpUpdater', dmp: json, debug: debug)
      true
    end
    end
  end
end
