# frozen_string_literal: true

require 'aws-sdk-dynamodb'

require 'dmp_helper'
require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'
require 'validator'

# -------------------------------------------------------------------------
# Dynamo Table Helper for updating DMP items
#
# Shared helper methods for Lambdas that interact with the DynamoDB Table
# -------------------------------------------------------------------------
class DmpUpdater
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Update a record in the table
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  # -------------------------------------------------------------------------
  def update_dmp(p_key:, json: {})
    json = Validator.parse_json(json: json)&.fetch('dmp', {})
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if json.nil? || p_key.nil?

    # Fail if the provenance is not defined
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if !@provenance.is_a?(Hash) ||
                                                                  @provenance['PK'].nil?

    # Verify that the JSON is for the same DMP in the PK
    dmp_id = json.fetch('dmp_id', {})
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } unless KeyHelper.dmp_id_to_pk(json: dmp_id) == p_key

    # Try to find it first and if not found return the result of the lookup
    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    result = finder.find_dmp_by_pk(p_key: p_key)
    return result unless result[:status] == 200

    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if result[:items].nil? || result[:items].empty?

    dmp = result[:items].first['dmp']
    # Only allow this if the provenance is the owner of the DMP!
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if dmp['dmphub_provenance_id'] != @provenance['PK']
    # Make sure they're not trying to update a historical copy of the DMP
    return { status: 405, error: Messages::MSG_DMP_NO_HISTORICALS } if dmp['SK'] != KeyHelper::DMP_LATEST_VERSION
    # Don's allow tombstoned DMPs to be updated
    return { status: 400, error: Messages::MSG_DMP_NOT_FOUND } if dmp['SK'] == KeyHelper::DMP_TOMBSTONE_VERSION

    # version the old :latest (Dynamo doesn't allow SK updates, so this creates a record)
    version_result = _version_it(dmp: dmp)
    return version_result unless version_result[:status] == 200

    old_version = version_result[:items].first
    json = _append_version_url(json: json, old_version: old_version)

    # Add the DMPHub specific attributes and then save it
    json = DmpHelper.annotate_dmp(provenance: @provenance, json: json, p_key: p_key)

    p 'JSON BEFORE SPLICING:' if @debug
    pp json if @debug

    json = _process_update(
      updater: @provenance['PK'], original_version: old_version, new_version: json
    )

    p 'JSON AFTER SPLICING:' if @debug
    pp json if @debug

    # Since the PK and SK are the same as the original record, this will just replace eveything
    response = @client.put_item({ table_name: @table, item: json, return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' })
    return { status: 500, error: Messages::MSG_SERVER_ERROR } unless response.successful?

    # Update the provenance keys!
    # Update the ancillary keys for orcids, affiliations, provenance

    finder = DmpFinder.new(provenance: @provenance, table_name: @table, client: @client, debug_mode: @debug)
    response = finder.find_dmp_by_pk(p_key: p_key, s_key: KeyHelper::DMP_LATEST_VERSION)
    return response unless response[:status] == 200

    # Send the updates to EZID, notify the provenance and download the PDF if applicable
    _post_process(provenance: provenance, p_key: p_key, json: json)

    { status: 200, items: response[:items] }
  rescue Aws::DynamoDB::Errors::DuplicateItemException
    { status: 405, error: Messages::MSG_DMP_EXISTS }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: "DmpUpdater.update_dmp - PK #{p_key}", message: e.message,
                        details: ([@provenance, json.inspect] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # ------------------------------------------------------------------------------------
  # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS MODULE
  # ------------------------------------------------------------------------------------

  # Convert the latest version into a historical version
  # rubocop:disable Metrics/AbcSize
  # -------------------------------------------------------------------------
  def _version_it(dmp:)
    return { status: 400, error: Messages::MSG_INVALID_ARGS } if dmp.nil? || dmp['PK'].nil? ||
                                                                 !dmp['PK'].start_with?(KeyHelper::PK_DMP_PREFIX)
    return { status: 403, error: Messages::MSG_DMP_NO_HISTORICALS } if dmp['SK'] != KeyHelper::DMP_LATEST_VERSION

    # Add a :previous_version_of identifier and set the new :SK
    dmp['dmproadmap_related_identifiers'] = [] if dmp['dmproadmap_related_identifiers'].nil?
    dmp['dmproadmap_related_identifiers'] << JSON.parse({
      descriptor: 'is_previous_version_of',
      work_type: 'output_management_plan',
      type: 'doi',
      identifier: dmp.fetch('dmp_id', {})['identifier']
    }.to_json)
    dmp['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{dmp['dmphub_updated_at'] || Time.now.iso8601}"

    # Create the prior version record
    response = @client.put_item({ table_name: @table, item: dmp, return_consumed_capacity: @debug ? 'TOTAL' : 'NONE' })
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } unless response.successful?

    { status: 200, items: [dmp] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: 'DmpUpdater._version_it', message: e.message,
                        details: ([@provenance, dmp.inspect] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end

  # rubocop:enable Metrics/AbcSize
  # Append the prior version to the latest version's :dmproadmap_related_identifiers
  # rubocop:disable Metrics/AbcSize
  def _append_version_url(json:, old_version:)
    return json unless json.is_a?(Hash) && old_version.is_a?(Hash) &&
                       !old_version['SK'].nil?

    version = old_version['SK'].gsub(KeyHelper::SK_DMP_PREFIX, '')
    uri = "#{KeyHelper.api_base_url}/dmps/#{KeyHelper.remove_pk_prefix(dmp: old_version['PK'])}?version=#{version}"
    json['dmproadmap_related_identifiers'] = [] if json['dmproadmap_related_identifiers'].nil?
    json['dmproadmap_related_identifiers'] << JSON.parse({
      descriptor: 'is_new_version_of',
      type: 'url',
      work_type: 'output_management_plan',
      identifier: uri
    }.to_json)
    json
  end
  # rubocop:enable Metrics/AbcSize

  # Process an update on the DMP metadata
  # --------------------------------------------------------------
  def _process_update(updater:, original_version:, new_version:)
    return nil if updater.nil? || new_version.nil?
    # If there is no :original_version then assume it's a new DMP
    return new_version if original_version.nil?
    # Return if there are no changes
    return original_version if DmpHelper.dmps_equal?(dmp_a: original_version, dmp_b: new_version)

    owner = original_version['dmphub_provenance_id']
    args = { owner: owner, updater: updater }

    # If the system of provenance is making the change then just use the
    # new version as the base and then splice in any mods made by others
    # args = args.merge({ base: new_version, mods: original_version })
    args = args.merge({ base: original_version, mods: new_version })
    return _splice_for_owner(args) if owner == updater

    # Otherwise use the original version as the base and then update the
    # metadata owned by the updater system
    args = args.merge({ base: original_version, mods: new_version })
    _splice_for_others(args)
  end

  # Once the DMP has been updated, we need to register it's DMP ID and download any
  # PDF if applicable
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def _post_process(provenance:, p_key:, json:)
    return false if p_key.nil? || p_key.to_s.strip.empty?

    unless provenance.fetch('seedingWithLiveDmpIds', 'false').to_s.downcase == 'true'
      Aws::SNS::Client.new.publish(
        topic_arn: SsmReader.get_ssm_value(key: SsmReader::SNS_PUBLISH_TOPIC),
        subject: "DmpUpdater - update DMP ID - #{p_key}",
        message: { action: 'update', provenance: @provenance['PK'], dmp: p_key }.to_json
      )
    end

    # Notify the Provenance system of changes if the provenance allows it
    # @provenance != json['dmphub_provenance_id'] &&
    #   !dmp_owner_provenance['callback_uri'].nil? # (needs to be fetched from Dynamo)
    return true unless json.is_a?(Hash) && json.fetch('dmproadmap_related_identifiers', []).any?

    dmp_urls = json['dmproadmap_related_identifiers'].select do |identifier|
      identifier['work_type'] == 'output_management_plan' && identifier['descriptor'] == 'is_metadata_for'
    end
    return true if dmp_urls.empty?

    Aws::SNS::Client.new.publish(
      topic_arn: SsmReader.get_ssm_value(key: SsmReader::SNS_DOWNLOAD_TOPIC),
      subject: "DmpUpdater - fetch DMP document - #{p_key}",
      message: { provenance: provenance['PK'], dmp: p_key, location: dmp_urls.first['identifier'] }.to_json
    )
    true
  end
  # rubocop:enable Metrics/AbcSize

  # These Splicing operations could probably be refined or genericized to traverse the Hash
  # and apply to each object

  # Splice changes from other systems onto the system of provenance's updated record
  # --------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def _splice_for_owner(owner:, updater:, base:, mods:)
    return base if owner.nil? || updater.nil? || mods.nil?
    return mods if base.nil?

    provenance_regex = /"dmphub_provenance_id":"#{KeyHelper::PK_PROVENANCE_PREFIX}[a-zA-Z\-_]+"/
    others = base.to_json.match(provenance_regex)
    # Just return it as is if there are no mods by other systems
    return mods if others.nil?

    spliced = DmpHelper.deep_copy_dmp(obj: base)
    cloned_mods = DmpHelper.deep_copy_dmp(obj: mods)

    # ensure that the :project and :funding are defined
    spliced['project'] = [{}] if spliced['project'].nil? || spliced['project'].empty?
    spliced['project'].first['funding'] = [] if spliced['project'].first['funding'].nil?
    # get all the new funding and retain other system's funding metadata
    mod_fundings = cloned_mods.fetch('project', [{}]).first.fetch('funding', [])
    other_fundings = spliced['project'].first['funding'].reject { |fund| fund['dmphub_provenance_id'].nil? }
    # process funding (just attach all funding not owned by the system of provenance)
    spliced['project'].first['funding'] = mod_fundings
    spliced['project'].first['funding'] << other_fundings if other_fundings.any?
    return spliced if cloned_mods['dmproadmap_related_identifiers'].nil?

    # process related_identifiers (just attach all related identifiers not owned by the system of provenance)
    spliced['dmproadmap_related_identifiers'] = [] if spliced['dmproadmap_related_identifiers'].nil?
    mod_relateds = cloned_mods.fetch('dmproadmap_related_identifiers', [])
    other_relateds = spliced['dmproadmap_related_identifiers'].reject { |id| id['dmphub_provenance_id'].nil? }
    spliced['dmproadmap_related_identifiers'] = mod_relateds
    spliced['dmproadmap_related_identifiers'] << other_relateds if other_relateds.any?
    spliced
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Splice changes from the other system onto the system of provenance and other system's changes
  # --------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def _splice_for_others(owner:, updater:, base:, mods:)
    return base if owner.nil? || updater.nil? || base.nil? || mods.nil?

    spliced = DmpHelper.deep_copy_dmp(obj: base)
    base_funds = spliced.fetch('project', [{}]).first.fetch('funding', [])
    base_relateds = spliced.fetch('dmproadmap_related_identifiers', [])

    mod_funds = mods.fetch('project', [{}]).first.fetch('funding', [])
    mod_relateds = mods.fetch('dmproadmap_related_identifiers', [])

    # process funding
    spliced['project'].first['funding'] = _update_funding(
      updater: updater, base: base_funds, mods: mod_funds
    )
    return spliced if mod_relateds.empty?

    # process related_identifiers
    spliced['dmproadmap_related_identifiers'] = _update_related_identifiers(
      updater: updater, base: base_relateds, mods: mod_relateds
    )
    spliced
  end
  # rubocop:enable Metrics/AbcSize

  # Splice funding changes
  # --------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def _update_funding(updater:, base:, mods:)
    return base if updater.nil? || mods.nil? || mods.empty?

    spliced = DmpHelper.deep_copy_dmp(obj: base)
    mods.each do |funding|
      # Ignore it if it has no status or grant id
      next if funding['funding_status'].nil? && funding['grant_id'].nil?

      # See if there is an existing funding record for the funder that's waiting on an update
      spliced = [] if spliced.nil?
      items = spliced.select do |orig|
        !orig['funder_id'].nil? &&
          orig['funder_id'] == funding['funder_id'] &&
          %w[applied planned].include?(orig['funding_status'])
      end
      # Always grab the most current
      items = items.sort { |a, b| b.fetch('dmphub_created_at', '') <=> a.fetch('dmphub_created_at', '') }
      item = items.first

      # Out with the old and in with the new
      spliced.delete(item) unless item.nil?
      # retain the original name
      funding['name'] = item['name'] unless item.nil?
      item = DmpHelper.deep_copy_dmp(obj: funding)

      item['funding_status'] == funding['funding_status'] unless funding['funding_status'].nil?
      spliced << item if funding['grant_id'].nil?
      next if funding['grant_id'].nil?

      item['grant_id'] = funding['grant_id']
      item['funding_status'] = funding['grant_id'].nil? ? 'rejected' : 'granted'

      # Add the provenance to the entry
      item['grant_id']['dmphub_provenance_id'] = updater
      item['grant_id']['dmphub_created_at'] = Time.now.iso8601
      spliced << item
    end
    spliced
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # Splice related identifier changes
  # --------------------------------------------------------------
  def _update_related_identifiers(updater:, base:, mods:)
    return base if updater.nil? || mods.nil? || mods.empty?

    # Remove the updater's existing related identifiers and replace with the new set
    spliced = base.nil? ? [] : DmpHelper.deep_copy_dmp(obj: base)
    spliced = spliced.reject { |related| related['dmphub_provenance_id'] == updater }
    # Add the provenance to the entry
    updates = mods.nil? ? [] : DmpHelper.deep_copy_dmp(obj: mods)
    updates = updates.map do |related|
      related['dmphub_provenance_id'] = updater
      related
    end
    spliced + updates
  end
end
