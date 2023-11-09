# frozen_string_literal: true

require 'bibtex'
require 'securerandom'

require 'uc3-dmp-citation'

module Uc3DmpId
  class AugmenterError < StandardError; end

  # Class that adds items to the :dmphub_modifications array or directly to the
  # :dmpraodmap_related_identifiers array if the confidence level was 'Absolute'
  class Augmenter
    attr_accessor :augmenter, :run_id, :dmp, :known_mods, :known_works, :known_awards, :logger

    MSG_MISSING_ANNOTATIONS = 'DMP must have its DMPHub specific annotations!'
    MSG_MISSING_AUGMENTER = 'No Augmenter specified!'
    MSG_MISSING_DMP = 'No DMP or the DMP did not contain enough information to use.'

    # rubocop:disable Metrics/AbcSize
    def initialize(**args)
      @logger = args[:logger]
      @augmenter = args[:augmenter]
      @run_id = args.fetch(:run_id, 'None')
      raise AugmenterError, MSG_MISSING_AUGMENTER unless @augmenter.is_a?(Hash) && !@augmenter['PK'].nil?

      @dmp = args.fetch(:dmp, {})['dmp'].nil? ? args[:dmp] : args.fetch(:dmp, {})['dmp']
      raise AugmenterError, MSG_MISSING_DMP if @dmp.nil? || @dmp['dmp_id'].nil?
      raise AugmenterError, MSG_MISSING_ANNOTATIONS if @dmp['PK'].nil?

      _extract_known
    end
    # rubocop:enable Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def add_modifications(works:)
      mod_hash = _generate_mod_header

      %w[publications datasets softwares].each do |work_type|
        works.fetch(work_type, []).each do |work|
          next if @known_works.include?(work['id'])

          work_hash = _work_to_mod_entry(type: work_type[0..work_type.length - 2], work:)
          mod_hash.fetch('dmproadmap_related_identifiers', []) << work_hash unless work_hash.nil?
          fundings = work.fetch('fundingReferences', [])
          next unless fundings.any?

          award_hash = fundings.map { |funding| _funding_to_mod_entry(work:, funding:) }
          mod_hash.fetch('funding', []) << award_hash unless award_hash.nil?
        end
      end
      return 0 unless mod_hash['dmproadmap_related_identifiers'].any? || mod_hash.fetch('funding', []).any?

      # A single work can have multiple fundingReferences, so flatten the array
      mod_hash['funding'] = mod_hash.fetch('funding', []).flatten.compact.uniq

      # Save the DMP
      @dmp['dmphub_modifications'] = (@known_mods.nil? ? [] : @known_mods) << mod_hash
      client = Uc3DmpDynamo::Client.new
      resp = client.put_item(json: @dmp, logger:)
      raise AugmenterError, Helper::MSG_DMP_NO_DMP_ID if resp.nil?

      # Return the number of modifications added to the DMP
      mod_hash.fetch('dmproadmap_related_identifiers', []).length + mod_hash.fetch('funding', []).length
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    def _generate_mod_header
      JSON.parse({
        id: "#{Time.now.utc.strftime('%Y-%m-%d')}-#{SecureRandom.hex(4)}",
        provenance: @augmenter['name'],
        augmenter_run_id: @run_id,
        timestamp: Time.now.utc.iso8601,
        dmproadmap_related_identifiers: [],
        funding: []
      }.to_json)
    end

    # rubocop:disable Metrics/AbcSize
    def _work_to_mod_entry(type:, work:)
      return nil if work['id'].nil?

      ret = {
        type: 'doi',
        identifier: work['id'],
        descriptor: 'references',
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        citation: work['citation']
      }
      work_type = work.fetch('type', 'Text')&.downcase&.strip
      ret[:work_type] = work_type == 'text' ? type : work_type
      @logger&.debug(message: "Assessing Work: #{work['id']} (pre citation)", details: ret)
      return JSON.parse(ret.to_json) if work['bibtex'].nil? || !ret[:citation].nil?

      ret[:citation] = Uc3DmpCitation::Citer.bibtex_to_citation(uri: work['id'], bibtex_as_string: work['bibtex'])
      JSON.parse(ret.to_json)
    end
    # rubocop:enable Metrics/AbcSize

    # Convert a funding entry for the dmphub_modification
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def _funding_to_mod_entry(work:, funding:)
      return nil unless funding.is_a?(Hash) && (!funding['awardUri'] || !funding['awardNumber'])
      return nil if @known_awards.include?(funding['awardUri']) || @known_awards.include?(funding['awardNumber'])

      id = funding['awardUri'] if funding.fetch('awardUri', '')&.start_with?('http')
      id = funding['awardNumber'] if id.nil?

      ret = {
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        name: funding['funderName'],
        funding_status: id.nil? ? 'planned' : 'granted'
      }
      id_type = id.start_with?('http') ? (id.include?('doi') ? 'doi' : 'url') : 'other' unless id.nil?
      ret[:grant_id] = { type: id_type, identifier: id } unless id.nil?

      funder_id = funding['funderIdentifier']
      @logger&.debug(message: "Assessing Work: #{work['id']} (pre funder_id)", details: ret)
      return JSON.parse(ret.to_json) if funder_id.nil?

      ret[:funder_id] = {
        type: if funder_id.include?('ror')
                'ror'
              else
                (funder_id.start_with?('http') ? 'url' : 'other')
              end,
        identifier: funder_id
      }
      JSON.parse(ret.to_json)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Retrieve all of the known modifications, related identifiers and awards from the DMP
    # rubocop:disable Metrics/AbcSize
    def _extract_known
      @known_mods = @dmp.fetch('dmphub_modifications', [])

      ids = @dmp.fetch('dmproadmap_related_identifiers', []).map { |id| id['identifier'] }
      ids += @known_mods.map { |m| m.fetch('dmproadmap_related_identifiers', []).map { |i| i['identifier'] } }
      @known_works = ids.flatten.compact.uniq

      fundings = @dmp.fetch('project', []).map { |proj| proj.fetch('funding', []) }.flatten.compact.uniq
      awards = fundings.map { |fund| [fund['dmproadmap_funding_opportunity_id'], fund['grant_id']] }
                       .flatten.compact.uniq

      awards += @known_mods.map do |mod|
        mod.fetch('funding', []).map { |fund| [fund['dmproadmap_funding_opportunity_id'], fund['grant_id']] }
      end
      @known_awards = awards.flatten.compact.uniq.map { |award| award['identifier'] }.flatten.compact.uniq
    end
    # rubocop:enable Metrics/AbcSize
  end
end
