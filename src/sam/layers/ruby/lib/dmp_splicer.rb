# frozen_string_literal: true

require 'key_helper'

# -------------------------------------------------------------------------------------
# DMP Versioner
#
# Class that handles versioning of DMP metadata
# -------------------------------------------------------------------------------------
class DmpSplicer
  class << self
    # Splice changes from other systems onto the system of provenance's updated record
    # --------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def splice_for_owner(owner:, updater:, base:, mods:, debug: false)
      source = 'DmpSplicer.splice_for_owner'
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

      if debug
        Responder.log_message(source: source, message: 'JSON after splicing in changes from provenance',
                              details: spliced)
      end
      spliced
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Splice changes from the other system onto the system of provenance and other system's changes
    # --------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def splice_for_others(owner:, updater:, base:, mods:, debug: false)
      source = 'DmpSplicer.splice_for_others'
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
      if debug
        Responder.log_message(source: source, message: 'JSON after splicing in changes from non-provenance',
                              details: spliced)
      end
      spliced
    end
    # rubocop:enable Metrics/AbcSize

    private

    # These Splicing operations could probably be refined or genericized to traverse the Hash
    # and apply to each object

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
end
