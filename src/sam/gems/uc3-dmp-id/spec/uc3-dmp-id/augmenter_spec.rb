# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Augmenter' do
  let!(:dmp) do
    ret = mock_dmp
    ret['dmp']['PK'] = "DMP##{ret['dmp'].fetch('dmp_id', {}).fetch('identifier', 'test').gsub('https://', '')}"
    ret['dmp']['SK'] = 'VERSION#latest'
    ret
  end
  let!(:augmenter) { JSON.parse({ PK: 'AUGMENTERS#tester', SK: 'PROFILE', name: 'Tester' }.to_json) }

  let!(:described_class) { Uc3DmpId::Augmenter }

  before do
    mock_uc3_dmp_dynamo(dmp:)
  end

  describe 'initialize(**args)' do
    context 'when initializing with valid arguments' do
      it 'sets the augmenter attribute' do
        aug = described_class.new(augmenter:, dmp:)
        expect(aug.augmenter).to eq(augmenter)
      end

      it 'sets the dmp attribute' do
        aug = described_class.new(augmenter:, dmp:)
        expect(aug.dmp).to eq(dmp['dmp'])
      end
    end

    context 'when initializing with missing or empty Augmenter' do
      it 'raises a AugmenterError' do
        expect do
          described_class.new(augmenter: {}, dmp:)
        end.to raise_error(Uc3DmpId::AugmenterError, Uc3DmpId::Augmenter::MSG_MISSING_AUGMENTER)
      end
    end

    context 'when initializing with missing or empty DMP' do
      it 'raises a AugmenterError' do
        expect do
          described_class.new(augmenter:, dmp: {})
        end.to raise_error(Uc3DmpId::AugmenterError, Uc3DmpId::Augmenter::MSG_MISSING_DMP)
      end
    end

    context 'when initializing with a DMP that does not include it\'s dmphub annotations (e.g. PK, SK)' do
      it 'raises a AugmenterError' do
        dmp['dmp'].delete('PK')
        expect do
          described_class.new(augmenter:, dmp:)
        end.to raise_error(Uc3DmpId::AugmenterError, Uc3DmpId::Augmenter::MSG_MISSING_ANNOTATIONS)
      end
    end

    context 'when calling _extract_known' do
      let!(:mods) do
        JSON.parse([
          {
            id: 'TEST',
            provenance: augmenter['name'],
            timestamp: Time.now.utc.iso8601,
            dmproadmap_related_identifiers: [
              {
                type: 'doi',
                identifier: 'https://doi.org/10.99999/887766',
                descriptor: 'references',
                status: 'pending'
              }
            ],
            funding: [
              {
                status: 'pending',
                name: 'Test Funder',
                funding_status: 'granted',
                grant_id: { type: 'other', identifier: 'test-foo' },
                dmproadmap_funding_opportunity_id: { type: 'other', identifier: 'test-bar' }
              }
            ]
          }
        ].to_json)
      end

      it 'sets the @known_mods array to an empty array if the DMP does not already have any' do
        dmp['dmp'].delete('dmphub_modifications')
        instance = described_class.new(augmenter:, dmp:)
        expect(instance.known_mods).to eql([])
      end

      it 'sets the @known_mods array' do
        dmp['dmp']['dmphub_modifications'] = mods
        instance = described_class.new(augmenter:, dmp:)
        expect(instance.known_mods).to eql(mods)
      end

      it 'sets the @known_works array to an empty array if the DMP does not already have any' do
        mods.first.delete('dmproadmap_related_identifiers')
        dmp['dmp'].delete('dmproadmap_related_identifiers')
        dmp['dmp']['dmphub_modifications'] = mods
        instance = described_class.new(augmenter:, dmp:)
        expect(instance.known_works).to eql([])
      end

      it 'sets the @known_works array' do
        dmp['dmp']['dmphub_modifications'] = mods
        dmp['dmp'].delete('dmproadmap_related_identifiers')
        dmp['dmp']['dmproadmap_related_identifiers'] = JSON.parse([{ identifier: 'foo-id', type: 'other' }].to_json)
        instance = described_class.new(augmenter:, dmp:)
        expected = ['foo-id', mods.first['dmproadmap_related_identifiers'].first['identifier']]
        expect(instance.known_works).to eql(expected)
      end

      it 'sets the @known_awards array to an empty array if the DMP does not already have any' do
        mods.first.delete('funding')
        dmp['dmp']['dmphub_modifications'] = mods
        dmp['dmp'].delete('project')
        instance = described_class.new(augmenter:, dmp:)
        expect(instance.known_awards).to eql([])
      end

      it 'sets the @known_awards array' do
        dmp['dmp']['dmphub_modifications'] = mods
        dmp['dmp'].delete('project')
        dmp['dmp']['project'] = JSON.parse([{ funding: [{ grant_id: { identifier: 'foo-grant' } }] }].to_json)
        instance = described_class.new(augmenter:, dmp:)
        expected = [
          'foo-grant',
          mods.first['funding'].first['dmproadmap_funding_opportunity_id']['identifier'],
          mods.first['funding'].first['grant_id']['identifier']
        ]
        expect(instance.known_awards).to eql(expected)
      end
    end
  end

  describe 'add_modifications(works:)' do
    let!(:instance) { described_class.new(augmenter:, dmp:) }

    it 'does not add modifications when no publications are provided' do
      dmp['dmp']['dmphub_modifications'] = []
      result = instance.add_modifications(works: JSON.parse({ publications: [] }.to_json))

      # Ensure that no modifications are added, and the result is 0
      expect(result).to eq(0)
      expect(instance.instance_variable_get(:@dmp)['dmphub_modifications']).to be_empty
    end

    it 'adds modifications for new publications' do
      # Simulate a scenario with new publications
      publications = [{ id: 1 }]
      allow(instance).to receive_messages(_work_to_mod_entry: {}, _funding_to_mod_entry: {})
      result = instance.add_modifications(works: JSON.parse({ publications: }.to_json))

      # Ensure that modifications are added, and the result is the number of modifications added
      expect(result).to eq(1)
      expect(instance.instance_variable_get(:@dmp)['dmphub_modifications']).not_to be_empty
    end

    it 'skips known publications' do
      dmp['dmp']['dmphub_modifications'] = []
      # Simulate a scenario where a publication is already known
      publications = [{ id: 1 }]
      instance.instance_variable_set(:@known_works, [1])

      result = instance.add_modifications(works: JSON.parse({ publications: }.to_json))

      # Ensure that no modifications are added, and the result is 0
      expect(result).to eq(0)
      expect(instance.instance_variable_get(:@dmp)['dmphub_modifications']).to be_empty
    end

    it 'handles publications with funding references' do
      dmp['dmp']['dmphub_modifications'] = []
      # Simulate a scenario with publications having funding references
      publications = [{ id: 1, fundingReferences: [{ award: '123' }] }]
      allow(instance).to receive_messages(_work_to_mod_entry: {}, _funding_to_mod_entry: {})

      result = instance.add_modifications(works: JSON.parse({ publications: }.to_json))

      # Ensure that modifications are added, and the result is the number of modifications added
      expect(result).to eq(2)
      expect(instance.instance_variable_get(:@dmp)['dmphub_modifications']).not_to be_empty
    end
  end

  describe '_generate_mod_header' do
    let!(:instance) { described_class.new(augmenter:, dmp:) }

    # rubocop:disable RSpec/ExampleLength
    it 'returns a valid JSON object with the expected keys' do
      result = instance.send(:_generate_mod_header)

      expected_result = JSON.parse({
        'id' => /^20\d{2}-\d{2}-\d{2}-[0-9a-f]{8}$/, # Regular expression to match the generated id format
        'provenance' => augmenter['name'],
        'timestamp' => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, # Regular expression to match ISO 8601 timestamp
        'dmproadmap_related_identifiers' => [],
        'funding' => []
      }.to_json)

      # Ensure that the 'id' matches the regular expression format
      expect(result['id']).to match(expected_result['id'])

      # Compare the other keys with their expected values
      expect(result['provenance']).to eq(expected_result['provenance'])
      expect(result['timestamp']).to match(expected_result['timestamp'])
      expect(result['dmproadmap_related_identifiers']).to eq(expected_result['dmproadmap_related_identifiers'])
      expect(result['funding']).to eq(expected_result['funding'])
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_work_to_mod_entry(type:, work:)' do
    let!(:instance) { described_class.new(augmenter:, dmp:) }

    before do
      allow(Uc3DmpCitation::Citer).to receive(:bibtex_to_citation).and_return('FOO!')
    end

    it 'returns nil when work id is nil' do
      work = { 'id' => nil }
      result = instance.send(:_work_to_mod_entry, type: 'some_type', work:)
      expect(result).to be_nil
    end

    # rubocop:disable RSpec/ExampleLength
    it 'returns a mod entry with type, identifier, descriptor, and status' do
      work = {
        'id' => 'doi:12345',
        'type' => 'Text',
        'bibtex' => 'BibTeX content',
        'confidence' => 'Test',
        'score' => 2,
        'notes' => %w[foo bar]
      }
      result = instance.send(:_work_to_mod_entry, type: 'some_type', work:)

      expected_result = JSON.parse({
        citation: 'FOO!',
        type: 'doi',
        identifier: 'doi:12345',
        descriptor: 'references',
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        work_type: 'some_type'
      }.to_json)
      expect(result).to eq(expected_result)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'handles work type as "Text" and assigns the provided type' do
      work = {
        'id' => 'doi:12345',
        'type' => 'Text',
        'bibtex' => 'BibTeX content',
        'confidence' => 'Test',
        'score' => 2,
        'notes' => %w[foo bar]
      }
      result = instance.send(:_work_to_mod_entry, type: 'custom_type', work:)

      expected_result = JSON.parse({
        citation: 'FOO!',
        type: 'doi',
        identifier: 'doi:12345',
        descriptor: 'references',
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        work_type: 'custom_type'
      }.to_json)
      expect(result).to eq(expected_result)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'returns nil for citation when work bibtex is nil' do
      work = {
        'id' => 'doi:12345',
        'type' => 'Text',
        'bibtex' => nil,
        'confidence' => 'Test',
        'score' => 2,
        'notes' => %w[foo bar]
      }
      result = instance.send(:_work_to_mod_entry, type: 'some_type', work:)

      expected_result = JSON.parse({
        type: 'doi',
        identifier: 'doi:12345',
        descriptor: 'references',
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        work_type: 'some_type'
      }.to_json)
      expect(result).to eq(expected_result)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_funding_to_mod_entry(work:, funding:)' do
    let!(:instance) { described_class.new(augmenter:, dmp:) }
    let!(:work) { JSON.parse({ confidence: 'Test', score: 2, notes: %w[foo bar] }.to_json) }
    before do
      known_awards = %w[known_award1 known_award2]
      instance.known_awards = known_awards
    end

    it 'returns nil when given nil funding' do
      result = instance.send(:_funding_to_mod_entry, work:, funding: nil)
      expect(result).to be_nil
    end

    it 'returns nil when awardUri and awardNumber are present in known_awards' do
      funding = { 'awardUri' => 'known_award1', 'funderName' => 'Funder' }
      result = instance.send(:_funding_to_mod_entry, work:, funding:)
      expect(result).to be_nil
    end

    # rubocop:disable RSpec/ExampleLength
    it 'returns the correct mod entry for a valid funding entry' do
      funding = {
        'awardNumber' => '12345',
        'funderName' => 'Funder',
        'funderIdentifier' => 'http://example.com'
      }
      result = instance.send(:_funding_to_mod_entry, work:, funding:)

      expected_result = JSON.parse({
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        name: 'Funder',
        funding_status: 'granted',
        grant_id: {
          type: 'other',
          identifier: '12345'
        },
        funder_id: {
          type: 'url',
          identifier: 'http://example.com'
        }
      }.to_json)
      expect(result).to eq(expected_result)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'returns the correct mod entry for a funding entry with a DOI' do
      funding = {
        'awardUri' => 'http://example.com/doi/12345',
        'funderName' => 'Funder'
      }
      result = instance.send(:_funding_to_mod_entry, work:, funding:)

      expected_result = JSON.parse({
        status: 'pending',
        confidence: work['confidence'],
        score: work['score'],
        notes: work['notes'],
        name: 'Funder',
        funding_status: 'granted',
        grant_id: {
          type: 'doi',
          identifier: 'http://example.com/doi/12345'
        }
      }.to_json)
      expect(result).to eq(expected_result)
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
