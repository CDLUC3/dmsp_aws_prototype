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
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Create the new version in Dynamo and then return the DMP metadata with a reference to the old version
  # rubocop:disable Metrics/AbcSize
  # -------------------------------------------------------------------------
  def new_version(p_key:, dmp:)
    source = 'DmpVersioner.process'
    return nil if p_key.nil? || !_versionable?(dmp: dmp)

    latest = _fetch_latest(p_key: p_key)
    # Only continue if there was an existing record and its the latest version
    return nil unless latest.is_a?(Hash) && latest['SK'] != KeyHelper::DMP_LATEST_VERSION

    owner = latest['dmphub_provenance_id']
    updater = @provenance['PK']
    prior = _generate_version(latest_version: latest, owner: owner, updater: updater)
    return nil if prior.nil?

    args = { owner: owner, updater: updater, base: prior, mods: dmp, debug: debug }
    log_message(source: source, message: 'JSON before splicing changes', details: dmp) if debug

    # If the system of provenance is making the change then just use the
    # new version as the base and then splice in any mods made by others
    # args = args.merge({ base: new_version, mods: original_version })
    new_version = DmpSplicer.splice_for_owner(args) if owner == updater
    # Otherwise use the original version as the base and then update the
    # metadata owned by the updater system
    new_version = DmpSplicer.splice_for_others(args) if new_version.nil?
    new_version
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([@provenance, dmp.inspect] << e.backtrace).flatten)
    nil
  end
  # rubocop:enable Metrics/AbcSize

  # Create the version history as an array for the dmp. For example:
  #   "dmphub_versions": [
  #     {
  #       "timestamp": "2022-02-05T07:06:08+00:00",
  #       "url": "https://example.com/api/v0/dmps/10.12345/ABCDEFG"
  #     }
  #     {
  #       "timestamp": "2022-01-28T17:52:14+00:00",
  #       "url": "https://example.com/api/v0/dmps/10.12345/ABCDEFG?version=2022-01-28T17:52:14+00:00"
  #     }
  #   ]
  # rubocop:disable Metrics/AbcSize
  def versions(p_key:, dmp:)
    source = "DmpVersioner.versions - PK: #{p_key}"
    return dmp if p_key.nil? || !dmp.is_a?(Hash)

    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    result = finder.find_dmp_versions(p_key: p_key)
    return dmp if result[:status] != 200 || result[:items].nil? || result[:items].empty?

    base_api_url = "#{SsmReader.get_ssm_value(key: SsmReader::API_BASE_URL)}/dmps/"
    # Get all but the latest version
    versions = result[:items].map do |version|
      timestamp = version['dmphub_updated_at'] if version['SK'] == KeyHelper::DMP_LATEST_VERSION
      timestamp = version['SK'].gsub(KeyHelper::SK_DMP_PREFIX, '') if timestamp.nil?
      {
        timestamp: timestamp,
        url: "#{base_api_url}#{version['PK'].gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{timestamp}"
      }
    end

    dmp['dmphub_versions'] = JSON.parse(versions.to_json)
    dmp
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([@provenance, dmp.inspect] << e.backtrace).flatten)
    dmp
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
  # rubocop:disable Metrics/AbcSize,  Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity
  def _generate_version(latest_version:, owner:, updater:)
    source = 'DmpVersioner._generate_version'
    # Only create a version if the Updater is not the Owner OR the changes have happened on a different day
    mod_time = Time.parse(latest_version.fetch('dmphub_updated_at', Time.now.iso8601))
    now = Time.now
    return latest_version if mod_time.nil? || !(now - mod_time).is_a?(Float)

    same_hour = (now - mod_time).round <= 3600
    return latest_version if owner != updater || (owner == updater && same_hour)

    latest_version['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{latest_version['dmphub_updated_at'] || Time.now.iso8601}"

    # Create the prior version record
    response = @client.put_item({ table_name: @table, item: latest_version,
                                  return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' })
    return nil unless response.successful?

    log_message(source: source, message: 'Created new version', details: latest_version) if debug
    latest_version
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([@provenance, latest_version.inspect] << e.backtrace).flatten)
    nil
  end
  # rubocop:enable Metrics/AbcSize,  Metrics/CyclomaticComplexity,  Metrics/PerceivedComplexity

  # Fetch the latest version of the DMP
  def _fetch_latest(p_key:)
    # Try to find it first and if not found return the result of the lookup
    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    result = finder.find_dmp_by_pk(p_key: p_key)
    return nil if result[:status] != 200 || result[:items].nil? || result[:items].empty?

    result[:items].first['dmp']
  end
end
