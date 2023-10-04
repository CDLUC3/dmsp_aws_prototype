# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Asserter' do
  let!(:described_class) { Uc3DmpId::Asserter }

  let!(:owner) { 'PROVENANCE#foo' }
  let!(:updater) { 'PROVENANCE#bar' }

  let!(:latest_version) { mock_dmp['dmp'] }

  before do
    latest_version['dmphub_provenance_id'] = owner
  end

  describe 'add(updater:, latest_version:, modified_version:, note: nil, logger: nil)' do
    let!(:new_mods) do
      JSON.parse({
        project: [
          title: 'foo ... testing',
          funding: [
            {
              name: 'Reliable cash.net',
              grant_id: {
                type: 'other', identifier: 'TESTING MONEY'
              }
            }
          ]
        ],
        dmproadmap_related_identifiers: [
          { work_type: 'image', descriptor: 'annoys', type: 'other', identifier: 'testing_one' },
          { type: 'other', identifier: 'testing_two' }
        ]
      }.to_json)
    end

    it 'returns the :latest_version as-is if the :updater is not a String' do
      result = described_class.add(updater: nil, latest_version:, modified_version: new_mods)
      expect(result).to eql(latest_version)
    end

    it 'returns the :latest_version as-is if the :latest_version is not a Hash' do
      result = described_class.add(updater:, latest_version: 123, modified_version: new_mods)
      expect(result).to be(123)
    end

    it 'returns the :latest_version as-is if the :modified_version is not a Hash' do
      result = described_class.add(updater:, latest_version:, modified_version: nil)
      expect(result).to eql(latest_version)
    end

    it 'returns the :latest_version as-is if the :updater is the owner of the DMP ID (owner do not assert!)' do
      latest_version['dmphub_provenance_id'] = updater
      result = described_class.add(updater:, latest_version:, modified_version: new_mods)
      expect(result).to eql(latest_version)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'adds the :dmphub_modifications if there are only :dmproadmap_related_identifiers' do
      new_mods.delete('project')
      result = described_class.add(updater:, latest_version:, modified_version: new_mods)
      changes = result['dmphub_modifications'].reject { |mod| mod.fetch('dmproadmap_related_identifiers', []).empty? }
      changes = changes.map { |change| change['dmproadmap_related_identifiers'] }.flatten

      work_one = changes.select do |work|
        work['identifier'] == new_mods['dmproadmap_related_identifiers'].first['identifier']
      end
      work_two = changes.select do |work|
        work['identifier'] == new_mods['dmproadmap_related_identifiers'].last['identifier']
      end

      expect(work_one.first['work_type']).to eql(new_mods['dmproadmap_related_identifiers'].first['work_type'])
      expect(work_one.first['descriptor']).to eql(new_mods['dmproadmap_related_identifiers'].first['descriptor'])
      expect(work_one.first['type']).to eql(new_mods['dmproadmap_related_identifiers'].first['type'])
      expect(work_one.first['identifier']).to eql(new_mods['dmproadmap_related_identifiers'].first['identifier'])

      expect(work_two.first['work_type']).to eql(described_class::DEFAULT_WORK_TYPE)
      expect(work_two.first['descriptor']).to eql(described_class::DEFAULT_DESCRIPTOR)
      expect(work_two.first['type']).to eql(new_mods['dmproadmap_related_identifiers'].last['type'])
      expect(work_two.first['identifier']).to eql(new_mods['dmproadmap_related_identifiers'].last['identifier'])
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    it 'adds the :dmphub_modifications if there is only a :grant_id' do
      new_mods.delete('dmproadmap_related_identifiers')
      result = described_class.add(updater:, latest_version:, modified_version: new_mods)
      fundings = result['dmphub_modifications'].reject { |mod| mod['funding'].nil? }.map { |m| m['funding'] }
      match = fundings.select do |fund|
        fund['grant_id'] == new_mods['project'].first['funding'].first['grant_id']
      end.first

      expect(match['grant_id']).to eql(new_mods['project'].first['funding'].first['grant_id'])
      expect(match['funding_status']).to eql('granted')
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'adds the :dmphub_modifications if there are both :dmproadmap_related_identifiers and a :grant_id' do
      result = described_class.add(updater:, latest_version:, modified_version: new_mods)
      changes = result['dmphub_modifications'].reject { |mod| mod.fetch('dmproadmap_related_identifiers', []).empty? }
      changes = changes.map { |change| change['dmproadmap_related_identifiers'] }.flatten

      fundings = result['dmphub_modifications'].reject { |mod| mod['funding'].nil? }.map { |m| m['funding'] }
      match = fundings.select do |fund|
        fund['grant_id'] == new_mods['project'].first['funding'].first['grant_id']
      end.first

      expect(match['grant_id']).to eql(new_mods['project'].first['funding'].first['grant_id'])
      expect(match['funding_status']).to eql('granted')

      work_one = changes.select do |work|
        work['identifier'] == new_mods['dmproadmap_related_identifiers'].first['identifier']
      end
      work_two = changes.select do |work|
        work['identifier'] == new_mods['dmproadmap_related_identifiers'].last['identifier']
      end

      expect(work_one.first['work_type']).to eql(new_mods['dmproadmap_related_identifiers'].first['work_type'])
      expect(work_one.first['descriptor']).to eql(new_mods['dmproadmap_related_identifiers'].first['descriptor'])
      expect(work_one.first['type']).to eql(new_mods['dmproadmap_related_identifiers'].first['type'])
      expect(work_one.first['identifier']).to eql(new_mods['dmproadmap_related_identifiers'].first['identifier'])

      expect(work_two.first['work_type']).to eql(described_class::DEFAULT_WORK_TYPE)
      expect(work_two.first['descriptor']).to eql(described_class::DEFAULT_DESCRIPTOR)
      expect(work_two.first['type']).to eql(new_mods['dmproadmap_related_identifiers'].last['type'])
      expect(work_two.first['identifier']).to eql(new_mods['dmproadmap_related_identifiers'].last['identifier'])
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
  end

  describe 'splice(latest_version:, modified_version:, logger: nil)' do
    let!(:new_mod) do
      JSON.parse({
        id: 'FOOOOOOO',
        provenance: 'dmphub',
        timestamp: '2023-08-20T05:06:07Z',
        note: 'data for testing mods',
        dmproadmap_related_identifiers: [
          { work_type: 'image', descriptor: 'annoys', type: 'other', identifier: 'bar.jpg' }
        ]
      }.to_json)
    end

    it 'returns the :modified_version if the :modified dates are the same' do
      modified = latest_version.dup
      modified['dmphub_modifications'] << new_mod
      result = described_class.splice(latest_version:, modified_version: modified)
      expect(assert_dmps_match(obj_a: modified, obj_b: result, debug: false)).to be(true)
    end

    it 'returns the :modified_version if neither has any :dmphub_modifications' do
      latest_version.delete('dmphub_modifications')
      modified = latest_version.dup
      result = described_class.splice(latest_version:, modified_version: modified)
      expect(assert_dmps_match(obj_a: modified, obj_b: result, debug: false)).to be(true)
    end

    it 'adds the incoming :dmphub_modifications to the latest_version when the latest_version has none' do
      latest_version.delete('dmphub_modifications')
      modified = latest_version.dup
      modified['dmphub_modifications'] = [new_mod]
      modified['modified'] = Time.now.utc.iso8601
      result = described_class.splice(latest_version:, modified_version: modified)
      expect(result['dmphub_modifications'].length).to be(1)
      expect(result['dmphub_modifications'].include?(new_mod)).to be(true)
    end

    it 'retains the existing :dmphub_modifications if the incoming has none' do
      modified = latest_version.dup
      modified.delete('dmphub_modifications')
      modified['modified'] = Time.now.utc.iso8601
      result = described_class.splice(latest_version:, modified_version: modified)
      expect(result['dmphub_modifications'].length).to be(3)
      latest_version['dmphub_modifications'].each do |mod|
        expect(result['dmphub_modifications'].include?(mod)).to be(true)
      end
    end

    it 'appends the incoming :dmphub_modifications to the ones on the existing record' do
      modified = latest_version.dup
      modified.delete('dmphub_modifications')
      modified['dmphub_modifications'] = [new_mod]
      modified['modified'] = Time.now.utc.iso8601
      result = described_class.splice(latest_version:, modified_version: modified)
      expect(result['dmphub_modifications'].length).to be(4)
      expect(result['dmphub_modifications'].include?(new_mod)).to be(true)
      latest_version['dmphub_modifications'].each do |mod|
        expect(result['dmphub_modifications'].include?(mod)).to be(true)
      end
    end
  end

  describe '_add_related_identifier(updater:, latest_version:, identifiers:, note: \'\', logger: nil)' do
    let!(:mods) do
      JSON.parse([
        {
          work_type: 'software',
          descriptor: 'cites',
          type: 'url',
          identifier: 'http://granter.org/12345.testing'
        }, {
          type: 'doi',
          identifier: 'http://99.66666/foo.testing/bar'
        }
      ].to_json)
    end

    it 'returns :latest_version as-is if :updater is not a String' do
      result = described_class.send(:_add_related_identifier, updater: 123, latest_version:,
                                                              identifiers: mods)
      expect(result).to eql(latest_version)
    end

    it 'returns :latest_version as-is if :latest_version is not a Hash' do
      result = described_class.send(:_add_related_identifier, updater:, latest_version: [123],
                                                              identifiers: mods)
      expect(result).to eql([123])
    end

    it 'returns :latest_version as-is if :identifiers is not an Array' do
      result = described_class.send(:_add_related_identifier, updater:, latest_version:,
                                                              identifiers: { foo: 'bar' })
      expect(result).to eql(latest_version)
    end

    it 'skips adding the :related_identifier if it is already in the :latest_version :dmphub_modifications Array' do
      latest_version['dmphub_modifications'] << JSON.parse({ dmproadmap_related_identifiers: [mods.first] }.to_json)
      result = described_class.send(:_add_related_identifier, updater:, latest_version:,
                                                              identifiers: mods)
      expect(result['dmphub_modifications'].length).to be(5)

      changes = result['dmphub_modifications'].reject { |mod| mod.fetch('dmproadmap_related_identifiers', []).empty? }
      changes = changes.map { |change| change['dmproadmap_related_identifiers'] }.flatten
      ids = changes.map { |mod| mod.fetch('identifier', '')&.downcase&.strip }.flatten.compact
      expect(ids.include?(mods.first['identifier'])).to be(true)
      expect(ids.select { |id| id == mods.first['identifier'] }.length).to be(1)
    end

    it 'skips adding the :related_identifier if it is already in the :latest_version :dmproadmap_related_identifiers' do
      tweaked_id = mods.first
      tweaked_id['descriptor'] = 'documents'
      latest_version['dmproadmap_related_identifiers'] << tweaked_id
      result = described_class.send(:_add_related_identifier, updater:, latest_version:,
                                                              identifiers: mods)
      expect(result['dmphub_modifications'].length).to be(4)

      changes = result['dmphub_modifications'].reject { |mod| mod.fetch('dmproadmap_related_identifiers', []).empty? }
      changes = changes.map { |change| change['dmproadmap_related_identifiers'] }.flatten
      ids = changes.map { |mod| mod.fetch('identifier', '')&.downcase&.strip }.flatten.compact.uniq
      expect(ids.include?(mods.first['identifier'])).to be(false)
    end

    it 'adds the :related_identifier assertion to the :latest_version :dmphub_modifications Array' do
      result = described_class.send(:_add_related_identifier, updater:, latest_version:,
                                                              identifiers: mods)
      expect(result['dmphub_modifications'].length).to be(4)

      changes = result['dmphub_modifications'].reject { |mod| mod.fetch('dmproadmap_related_identifiers', []).empty? }
      changes = changes.map { |change| change['dmproadmap_related_identifiers'] }.flatten
      ids = changes.map { |mod| mod.fetch('identifier', '')&.downcase&.strip }.flatten.compact.uniq
      mods.each { |mod| expect(ids.include?(mod['identifier'])).to be(true) }
    end
  end

  describe '_add_funding_mod(updater:, latest_version:, funding:, note: \'\', logger: nil)' do
    let!(:mods) do
      JSON.parse([{
        status: 'granted',
        grant_id: { type: 'url', identifier: 'http://granter.org/12345' }
      }].to_json)
    end

    it 'returns :latest_version as-is if :updater is not a String' do
      result = described_class.send(:_add_funding_mod, updater: 123, latest_version:, funding: mods)
      expect(result).to eql(latest_version)
    end

    it 'returns :latest_version as-is if :latest_version is not a Hash' do
      result = described_class.send(:_add_funding_mod, updater:, latest_version: [123], funding: mods)
      expect(result).to eql([123])
    end

    it 'returns :latest_version as-is if :funding is not an Array' do
      result = described_class.send(:_add_funding_mod, updater:, latest_version:,
                                                       funding: { foo: 'bar' })
      expect(result).to eql(latest_version)
    end

    it 'skips adding the :grant_id if it is already in the :latest_version :dmphub_modifications Array' do
      latest_version['dmphub_modifications'] << JSON.parse({ funding: mods.first }.to_json)
      result = described_class.send(:_add_funding_mod, updater:, latest_version:, funding: mods)
      expect(result['dmphub_modifications'].length).to be(4)
      fundings = result['dmphub_modifications'].reject { |mod| mod['funding'].nil? }.flatten.compact.uniq
      grants = fundings.map { |fund| fund.fetch('funding', {})['grant_id'] }
      expect(grants.include?(mods.first)).to be(false)
    end

    it 'skips adding the :grant_id if it is already in the :latest_version project: :funding Array' do
      latest_version['project'].first['funding'].first['grant_id'] = mods.first['grant_id']
      result = described_class.send(:_add_funding_mod, updater:, latest_version:, funding: mods)
      expect(result['dmphub_modifications'].length).to be(3)
      fundings = result['dmphub_modifications'].reject { |mod| mod['funding'].nil? }.flatten.compact.uniq
      grants = fundings.map { |fund| fund.fetch('funding', {})['grant_id'] }
      expect(grants.include?(mods.first)).to be(false)
    end

    it 'adds the :grant_id assertion to the :latest_version :dmphub_modifications Array' do
      result = described_class.send(:_add_funding_mod, updater:, latest_version:, funding: mods)
      expect(result['dmphub_modifications'].length).to be(4)
      fundings = result['dmphub_modifications'].reject { |mod| mod['funding'].nil? }.flatten.compact.uniq
      grants = fundings.map { |fund| fund.fetch('funding', {})['grant_id'] }
      expect(grants.include?(mods.first['grant_id'])).to be(true)
    end
  end

  describe '_generate_assertion(updater:, mods:, note: \'\')' do
    let!(:mods) do
      JSON.parse({
        dmproadmap_related_identifiers: [
          { work_type: 'dataset', descriptor: 'references', type: 'doi',
            identifier: 'https://doi.org/11.22222/3333344' },
          { work_type: 'article', descriptor: 'is_cited_by', type: 'doi',
            identifier: 'https://doi.org/11.22222/journalA/1' }
        ],
        funding: {
          status: 'granted',
          grant_id: { type: 'url', identifier: 'http://granter.org/12345' }
        }
      }.to_json)
    end

    it 'returns nil if the :updater is nil' do
      expect(described_class.send(:_generate_assertion, updater: nil, mods:, note: 'testing ...')).to be_nil
    end

    it 'returns nil if :mod is not a Hash' do
      expect(described_class.send(:_generate_assertion, updater:, mods: '123', note: 'testing ...')).to be_nil
    end

    # rubocop:disable RSpec/MultipleExpectations
    it 'returns the formatted assertion' do
      result = described_class.send(:_generate_assertion, updater:, mods:, note: 'testing ...')
      expect(result['id'].nil?).to be(false)
      expect(result['provenance']).to eql(updater.gsub('PROVENANCE#', ''))
      expect(result['timestamp'].nil?).to be(false)
      expect(result['status']).to eql('pending')
      expect(result['note']).to eql('testing ...')
      mods['dmproadmap_related_identifiers'].each do |mod|
        expect(result['dmproadmap_related_identifiers'].include?(mod)).to be(true)
      end
      expect(result['funding']).to eql(mods['funding'])
    end
    # rubocop:enable RSpec/MultipleExpectations
  end
end
