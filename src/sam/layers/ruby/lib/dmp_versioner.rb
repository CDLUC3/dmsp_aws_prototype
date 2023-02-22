# frozen_string_literal: true

require 'aws-sdk-dynamodb'

require 'dmp_splicer'
require 'key_helper'
require 'messages'
require 'responder'
require 'time'

# -------------------------------------------------------------------------------------
# DMP Versioner
#
# Class that handles versioning of DMP metadata. DMPs are versioned as new changes come in.
#
# Since DynamoDB does not allow us to change the PK or SK of the record, we take a snapshot
# of the existing latest version and set it's SK to the modification date and create the record.
#
# The pending changes are then applied directly to the latest version record
#
# A version is created ANY time the updater is not the system of provenance (owner). A new
# version also created if the pending changes are from a different day than the last modifications
# -------------------------------------------------------------------------------------
class DmpVersioner
  class << self
    # Create the new version in Dynamo and then return the DMP metadata with a reference to the old version
    # rubocop:disable Metrics/AbcSize
    # -------------------------------------------------------------------------
    def process(p_key:, dmp:, provenance:, client:, table:, debug: false)
      return { status: 400, error: Messages::MSG_EMPTY_JSON } if p_key.nil? || !_versionable?(dmp: dmp)

      latest = _fetch_latest(p_key: p_key, provenance: provenance, client: client, table: table, debug: debug)
      prior = _generate_version(
        provenance: provenance, client: client, table: table, debug: false,
        latest_version: latest, new_version: dmp
      )

      owner = latest['dmphub_provenance_id']
      updater = provenance['PK']
      args = { owner: owner, updater: updater, base: prior, mods: dmp }

      p 'JSON BEFORE SPLICING:' if debug
      p dmp if debug

      # If the system of provenance is making the change then just use the
      # new version as the base and then splice in any mods made by others
      # args = args.merge({ base: new_version, mods: original_version })
      return { status: 200, items: [DmpSplicer.splice_for_owner(args)] } if owner == updater

      # Otherwise use the original version as the base and then update the
      # metadata owned by the updater system
      { status: 200, items: [DmpSplicer.splice_for_others(args)] }
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: 'DmpVersioner.generate_version', message: e.message,
                          details: ([provenance, dmp.inspect] << e.backtrace).flatten)
      { status: 500, error: Messages::MSG_SERVER_ERROR }
    end
    # rubocop:enable Metrics/AbcSize

    private

    # Determine whether the specified DMP metadata is versionable - returns boolean
    def _versionable?(dmp:)
      return false unless dmp.is_a?(Hash)
      # It is versionable only if the entry we got does not have a PK/SK
      return false unless dmp['PK'].nil? && dmp['SK'].nil?

      # It's versionable if it has a DMP ID
      !dmp.fetch('dmp_id', {})['identifier'].nil?
    end

    # Generate a version
    def _generate_version(provenance:, client:, table:, latest_version:, new_version:, debug: false)
      # Only create a version if the Updater is not the Owner OR the changes have happened on a different day
      same_day = Time.parse(latest_version['dmphub_modification_day']) == Time.now.strftime('%Y-%M-%D')
      owner = latest_version['dmphub_provenance_id']
      updater = provenance['PK']
      return latest_version if owner != updater || (owner == updater && !same_day)

      latest_version = _add_previous_version_of(json: latest_version)
      latest_version['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{latest_version['dmphub_updated_at'] || Time.now.iso8601}"

      # Create the prior version record
      response = client.put_item({ table_name: table, item: latest_version, return_consumed_capacity: debug ? 'TOTAL' : 'NONE' })
      return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } unless response.successful?

      p "CREATED VERSION:" if debug
      p latest_version if debug

      latest_version
    end

    # Fetch the latest version of the DMP
    def _fetch_latest(p_key:, provenance:, client:, table:, debug: false)
      # Try to find it first and if not found return the result of the lookup
      finder = DmpFinder.new(provenance: provenance, table_name: table, client: client, debug_mode: debug)
      result = finder.find_dmp_by_pk(p_key: p_key)
      return result unless result[:status] == 200
      return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if result[:items].nil? || result[:items].empty?

      result[:items].first['dmp']
    end

    # Append the prior version to the latest version's :dmproadmap_related_identifiers
    # rubocop:disable Metrics/AbcSize
    # -------------------------------------------------------------------------
    def _add_previous_version_of(json:)
      return json unless json.is_a?(Hash)

      # Add a :previous_version_of identifier and set the new :SK
      json['dmproadmap_related_identifiers'] = [] if json['dmproadmap_related_identifiers'].nil?
      json['dmproadmap_related_identifiers'] << JSON.parse({
        descriptor: 'is_previous_version_of',
        work_type: 'output_management_plan',
        type: 'doi',
        identifier: json.fetch('dmp_id', {})['identifier']
      }.to_json)
      json
    end

    # Append the prior version to the latest version's :dmproadmap_related_identifiers
    # rubocop:disable Metrics/AbcSize
    # -------------------------------------------------------------------------
    def _add_new_version_of(new_version:, old_version:)
      return new_version unless new_version.is_a?(Hash) && old_version.is_a?(Hash) &&
                                !old_version['SK'].nil?

      version = old_version['SK'].gsub(KeyHelper::SK_DMP_PREFIX, '')
      uri = "#{KeyHelper.api_base_url}/dmps/#{KeyHelper.remove_pk_prefix(dmp: old_version['PK'])}?version=#{version}"
      new_version['dmproadmap_related_identifiers'] = [] if new_version['dmproadmap_related_identifiers'].nil?
      new_version['dmproadmap_related_identifiers'] << JSON.parse({
        descriptor: 'is_new_version_of',
        type: 'url',
        work_type: 'output_management_plan',
        identifier: uri
      }.to_json)
      new_version
    end
    # rubocop:enable Metrics/AbcSize
  end
end
