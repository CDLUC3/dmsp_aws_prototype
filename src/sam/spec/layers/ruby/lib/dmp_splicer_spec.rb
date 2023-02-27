# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpSplicer' do
  let!(:described_class) { DmpSplicer }

  let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'splice_for_owner(owner:, updater:, base:, mods:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:owner) { "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" }
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:mods) do
      JSON.parse({
        project: [
          funding: [{
            name: 'new_funder',
            funder_id: { type: 'url', identifier: 'http://new.org' },
            funding_status: 'applied'
          }]
        ],
        dmproadmap_related_identifiers: [
          { type: 'url', work_type: 'software', descriptor: 'references', identifier: 'http://github.com' }
        ]
      }.to_json)
    end

    before do
      dmp_item['dmphub_provenance_id'] = owner
    end

    it 'returns :base if :owner is nil' do
      expect(described_class.splice_for_owner(owner: nil, updater: updater, base: dmp_item,
                                              mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :updater is nil' do
      expect(described_class.splice_for_owner(owner: updater, updater: nil, base: dmp_item,
                                              mods: mods)).to eql(dmp_item)
    end

    it 'returns :mods if :base is nil' do
      expect(described_class.splice_for_owner(owner: owner, updater: updater, base: nil, mods: mods)).to eql(mods)
    end

    it 'returns :base if :mods is nil' do
      expect(described_class.splice_for_owner(owner: owner, updater: updater, base: dmp_item,
                                              mods: nil)).to eql(dmp_item)
    end

    it 'retains other system\'s metadata' do
      # funds and related identifiers that are not owned by the system of provenance have a provenance_id
      funds = dmp_item['project'].first['funding'].reject { |fund| fund['dmphub_provenance_id'].nil? }
      ids = dmp_item['dmproadmap_related_identifiers'].reject { |id| id['dmphub_provenance_id'].nil? }
      result = described_class.splice_for_owner(owner: owner, updater: updater, base: dmp_item, mods: mods)
      funds.each { |fund| expect(result['project'].first['funding'].include?(fund)).to be(true) }
      ids.each { |id| expect(result['dmproadmap_related_identifiers'].include?(id)).to be(true) }
    end

    it 'uses the :mods if :base has no :project defined' do
      dmp_item.delete('project')
      result = described_class.splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['project']).to eql(mods['project'])
    end

    it 'uses the :mods if :base has no :funding defined' do
      dmp_item['project'].first.delete('funding')
      result = described_class.splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['project'].first['funding']).to eql(mods['project'].first['funding'])
    end

    it 'updates the :funding' do
      result = described_class.splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      funds = dmp_item['project'].first['funding'].reject { |fund| fund['dmphub_provenance_id'].nil? }
      expected = mods['project'].first['funding'].length + funds.length
      expect(result['project'].first['funding'].length).to eql(expected)
      mods['project'].first['funding'].each do |fund|
        expect(result['project'].first['funding'].include?(fund)).to be(true)
      end
    end

    it 'updates the :dmproadmap_related_identifiers' do
      result = described_class.splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      ids = dmp_item['dmproadmap_related_identifiers'].reject { |id| id['dmphub_provenance_id'].nil? }
      expected = mods['dmproadmap_related_identifiers'].length + ids.length
      expect(result['dmproadmap_related_identifiers'].length).to eql(expected)
      mods['dmproadmap_related_identifiers'].each do |id|
        expect(result['dmproadmap_related_identifiers'].include?(id)).to be(true)
      end
    end

    it 'uses the :mods if :base has no :dmproadmap_related_identifiers defined' do
      dmp_item.delete('dmproadmap_related_identifiers')
      result = described_class.splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['dmproadmap_related_identifiers']).to eql(mods['dmproadmap_related_identifiers'])
    end
  end

  describe 'splice_for_others(owner:, updater:, base:, mods:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:owner) { "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" }
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:mods) do
      JSON.parse({
        project: [
          funding: [{
            name: 'new_funder',
            funder_id: { type: 'url', identifier: 'http://new.org' },
            funding_status: 'applied'
          }]
        ],
        dmproadmap_related_identifiers: [
          { type: 'url', work_type: 'software', descriptor: 'references', identifier: 'http://github.com' }
        ]
      }.to_json)
    end

    before do
      dmp_item['dmphub_provenance_id'] = owner
    end

    it 'returns :base if :owner is nil' do
      expect(described_class.splice_for_others(owner: nil, updater: updater, base: dmp_item,
                                               mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :updater is nil' do
      expect(described_class.splice_for_others(owner: owner, updater: nil, base: dmp_item,
                                               mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :base is nil' do
      expect(described_class.splice_for_others(owner: owner, updater: updater, base: nil, mods: mods)).to be_nil
    end

    it 'returns :base if :mods is nil' do
      expect(described_class.splice_for_others(owner: owner, updater: updater, base: dmp_item,
                                               mods: nil)).to eql(dmp_item)
    end

    it 'updates the :funding' do
      result = described_class.splice_for_others(owner: owner, updater: updater, base: dmp_item, mods: mods)
      expected = dmp_item['project'].first['funding'].length + 1
      expect(result['project'].first['funding'].length).to eql(expected)
    end

    it 'updates the :dmproadmap_related_identifiers' do
      result = described_class.splice_for_others(owner: owner, updater: updater, base: dmp_item, mods: mods)
      expected = dmp_item['dmproadmap_related_identifiers'].length + 1
      expect(result['dmproadmap_related_identifiers'].length).to eql(expected)
    end
  end

  describe '_update_funding(updater:, base:, mods:)' do
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:funder_id) { { type: 'ror', identifier: 'https://ror.org/12345' } }
    let!(:other_funder_id) { { type: 'ror', identifier: 'https://ror.org/09876' } }
    let!(:other_existing) { 'http://other.org/grants/333' }
    let!(:owner_existing) { 'http://owner.com/grants/123' }
    let!(:base) do
      JSON.parse([
        # System of provenance fundings
        { name: 'name-only', funding_status: 'applied' },
        { name: 'planned', funder_id: funder_id, funding_status: 'planned' },
        { name: 'granted', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'url', identifier: owner_existing } },

        # Other non-system of provenance fundings
        { name: 'name-only', funding_status: 'applied', dmphub_created_at: Time.now.iso8601,
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other" },
        { name: 'rejected', funder_id: other_funder_id, funding_status: 'rejected',
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other",
          dmphub_created_at: Time.now.iso8601 },
        { name: 'granted', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'url', identifier: other_existing },
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other",
          dmphub_created_at: Time.now.iso8601 }
      ].to_json)
    end

    it 'returns :base if the :updater is nil' do
      result = described_class.send(:_update_funding, updater: nil, base: base, mods: {})
      expect(result).to eql(base)
    end

    it 'returns :base if the :mods are empty' do
      result = described_class.send(:_update_funding, updater: updater, base: base, mods: nil)
      expect(result).to eql(base)
    end

    it 'returns the :mods if :base is nil' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      result = described_class.send(:_update_funding, updater: updater, base: nil, mods: mods)
      expect(result.length).to be(1)
      expect(result).to eql(mods)
    end

    it 'ignores entries that do not include the :funding_status or :grant_id' do
      mods = JSON.parse([
        { name: 'ignorable', funder_id: { type: 'url', identifier: 'http:/skip.me' } }
      ].to_json)
      result = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      expect(result.length).to eql(base.length)
    end

    it 'does not delete other systems\' entries' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      result = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      expect(result.length).to eql(base.length + 1)
      expect(result).to eql(base + mods)
    end

    it 'appends new entries' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      results = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['name'] == mods.first['name'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(mods.first['funder_id'])
      expect(result['funding_status']).to eql(mods.first['funding_status'])
      expect(result['grant_id'].nil?).to be(true)
    end

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'includes dmphub metadata when the new entry includes a :grant_id' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' },
          funding_status: 'granted', grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['name'] == mods.first['name'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(mods.first['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'updates the latest provenance system entry with grant metadata' do
      mods = JSON.parse([
        { name: 'arbitrary', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.last
      original = base.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.first

      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(original['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'adds a new entry if the DMP already has a \'rejected\' or \'granted\' entry for the funder' do
      mods = JSON.parse([
        { name: 'arbitrary', funder_id: other_funder_id, funding_status: 'granted',
          grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class.send(:_update_funding, updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.last
      original = base.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(original['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
  end

  describe '_update_related_identifiers(updater:, base:, mods:)' do
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:updater_existing) { 'http://33.11111/foo' }
    let!(:owner_existing) { 'http://owner.com' }
    let!(:other_existing) { 'http://33.22222/bar' }
    let!(:base) do
      JSON.parse([
        { descriptor: 'cites', work_type: 'software', type: 'url',
          identifier: owner_existing },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: other_existing,
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: updater_existing, dmphub_provenance_id: updater }
      ].to_json)
    end
    let!(:mods) do
      JSON.parse([
        { descriptor: 'cites', work_type: 'software', type: 'url',
          identifier: 'http://github.com/new' },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: 'http://33.22222/new' }
      ].to_json)
    end

    it 'returns :base if the :updater is nil' do
      result = described_class.send(:_update_related_identifiers, updater: nil, base: base, mods: mods)
      expect(result).to eql(base)
    end

    it 'returns :base if the :mods are empty' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: base, mods: nil)
      expect(result).to eql(base)
    end

    it 'returns :mods if the :base is nil' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: nil, mods: mods)
      mods.each { |mod| mod['dmphub_provenance_id'] = updater }
      expect(result).to eql(mods)
    end

    it 'removes existing entries for the updater' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == updater_existing }.length).to be(0)
    end

    it 'does NOT remove entries for other systems' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == other_existing }.length).to be(1)
    end

    it 'does NOT remove entries for the system of provenance' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == owner_existing }.length).to be(1)
    end

    it 'adds the updater\'s entries' do
      result = described_class.send(:_update_related_identifiers, updater: updater, base: base, mods: mods)
      updated = result.select { |i| i['dmphub_provenance_id'] == updater }
      expect(updated.length).to be(2)
    end
  end
end
