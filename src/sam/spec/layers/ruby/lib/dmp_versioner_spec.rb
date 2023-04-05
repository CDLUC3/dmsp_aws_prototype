# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpVersioner' do
  let!(:described_class) do
    DmpVersioner.new(
      provenance: provenance,
      table_name: 'bar',
      client: mock_dynamodb(item_array: []),
      debug_mode: false
    )
  end

  let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }
  let!(:provenance) { JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo" }.to_json) }
  let!(:p_key) { dmp['dmp']['PK'] }
  let!(:domain) { 'https://example.com/api/v0' }

  before do
    mock_ssm(value: domain)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'new_version(p_key:, dmp:)' do
    let!(:json) { dmp['dmp'] }

    it 'returns nil if :p_key is nil' do
      expect(described_class.new_version(p_key: nil, dmp: json)).to be_nil
    end

    it 'returns nil if :versionable? returns false' do
      allow(described_class).to receive(:_versionable?).and_return(false)
      expect(described_class.new_version(p_key: p_key, dmp: json)).to be_nil
    end

    it 'returns nil if the latest DMP could not be found' do
      allow(described_class).to receive(:_versionable?).and_return(true)
      allow(described_class).to receive(:_fetch_latest).and_return(nil)
      expect(described_class.new_version(p_key: p_key, dmp: json)).to be_nil
    end

    it 'returns nil if the DMP could not be versioned' do
      allow(described_class).to receive(:_versionable?).and_return(true)
      allow(described_class).to receive(:_fetch_latest).and_return(dmp)
      allow(described_class).to receive(:_generate_version).and_return(nil)
      expect(described_class.new_version(p_key: p_key, dmp: json)).to be_nil
    end

    it 'returns the new version' do
      allow(described_class).to receive(:_versionable?).and_return(true)
      allow(described_class).to receive(:_fetch_latest).and_return(dmp)

      prior = json.clone
      timestamp = Time.now.iso8601
      prior['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{timestamp}"
      prior['dmphub_modification_day'] = timestamp.split('T').first
      prior['dmphub_updated_at'] = timestamp
      prior['modified'] = timestamp
      allow(described_class).to receive(:_generate_version).and_return(prior)
      expect(described_class.new_version(p_key: p_key, dmp: json)).to eql(prior)
    end
  end

  describe 'versions(p_key:, dmp:)' do
    let!(:json) { dmp['dmp'] }

    it 'returns the :dmp as-is if the :p_key is nil' do
      expect(described_class.versions(p_key: nil, dmp: json)).to eql(dmp['dmp'])
    end

    it 'returns the :dmp as-is if the :dmp is not a Hash' do
      expect(described_class.versions(p_key: p_key, dmp: 'foo')).to eql('foo')
    end

    it 'returns the :dmp as-is if the DmpFinder could not find any versions for the :p_key' do
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_versions).and_return({ status: 404 })
      expect(described_class.versions(p_key: p_key, dmp: json)).to eql(json)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'appends the :dmphub_versions array when there is only one version' do
      json['SK'] = KeyHelper::DMP_LATEST_VERSION
      json['dmphub_modification_day'] = json['modified'].split('T').first
      json['dmphub_updated_at'] = json['modified']
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_versions).and_return({ status: 200, items: [json] })
      expected = JSON.parse(
        [
          {
            timestamp: json['modified'],
            url: "#{domain}/dmps/#{p_key.gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{json['modified']}"
          }
        ].to_json
      )
      expect(described_class.versions(p_key: p_key, dmp: json)['dmphub_versions']).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'appends the :dmphub_versions array when there are multiple versions' do
      json['SK'] = KeyHelper::DMP_LATEST_VERSION
      json['dmphub_modification_day'] = json['modified'].split('T').first
      json['dmphub_updated_at'] = json['modified']

      prior = json.clone
      timestamp = Time.now.iso8601
      prior['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{timestamp}"
      prior['dmphub_modification_day'] = timestamp.split('T').first
      prior['dmphub_updated_at'] = timestamp
      prior['modified'] = timestamp

      allow_any_instance_of(DmpFinder).to receive(:find_dmp_versions).and_return({ status: 200, items: [json, prior] })
      expected = JSON.parse(
        [
          {
            timestamp: json['modified'],
            url: "#{domain}/dmps/#{p_key.gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{json['modified']}"
          },
          {
            timestamp: prior['modified'],
            url: "#{domain}/dmps/#{p_key.gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{prior['modified']}"
          }
        ].to_json
      )
      expect(described_class.versions(p_key: p_key, dmp: json)['dmphub_versions']).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_versionable?(dmp:)' do
    it 'returns false if :dmp is not a Hash' do
      expect(described_class.send(:_versionable?, dmp: 'foo')).to be(false)
    end

    it 'returns false if dmp[:PK] is NOT nil' do
      expect(described_class.send(:_versionable?, dmp: JSON.parse({ PK: 'foo' }.to_json))).to be(false)
    end

    it 'returns false if dmp[:SK] is NOT nil' do
      expect(described_class.send(:_versionable?, dmp: JSON.parse({ SK: 'bar' }.to_json))).to be(false)
    end

    it 'returns true if :identifier from the dmp[:dmp_id] is NOT nil' do
      json = JSON.parse({ dmp_id: { identifier: 'foo' } }.to_json)
      expect(described_class.send(:_versionable?, dmp: json)).to be(true)
    end
  end

  describe '_generate_version(latest_version:, owner:, updater:)' do
    let!(:owner) { provenance['PK'] }

    it 'returns the :latest_version as-is if the updater is not the system of provenance' do
      updater = JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}bar" }.to_json)
      result = described_class.send(:_generate_version, latest_version: dmp, owner: owner, updater: updater)
      expect(result).to eql(dmp)
    end

    it 'returns the :latest_version as-is if the change is from the same hour as :dmphub_updated_at' do
      dmp['dmphub_updated_at'] = Time.now.iso8601
      result = described_class.send(:_generate_version, latest_version: dmp, owner: owner, updater: owner)
      expect(result).to eql(dmp)
    end

    it 'creates a new version if the chnage occured more than an hour before this update' do
      dmp['dmphub_updated_at'] = '2023-01-01T12:23:34+00:00'
      result = described_class.send(:_generate_version, latest_version: dmp, owner: owner, updater: owner)
      expect(result).to eql(dmp)
    end

    it 'returns nil if the Version could not be created' do
      dmp['dmphub_updated_at'] = '2023-01-01T12:23:34+00:00'
      described_class.client = mock_dynamodb(item_array: [], success: false)
      result = described_class.send(:_generate_version, latest_version: dmp, owner: owner, updater: owner)
      expect(result).to be_nil
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns the properly ammended :latest_version' do
      dmp['dmphub_updated_at'] = '2023-01-01T12:23:34+00:00'
      result = described_class.send(:_generate_version, latest_version: dmp, owner: owner, updater: owner)
      expect(result['SK']).to eql("#{KeyHelper::SK_DMP_PREFIX}#{dmp['dmphub_updated_at']}")
    end
  end

  describe '_fetch_latest(p_key:)' do
    it 'returns nil if the result from DmpFinder if the status is not 200' do
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 500 })
      expect(described_class.send(:_fetch_latest, { p_key: 'foo' })).to be_nil
    end

    it 'returns nil if the result from DmpFinder is empty' do
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [] })
      expect(described_class.send(:_fetch_latest, { p_key: 'foo' })).to be_nil
    end

    it 'returns the dmp' do
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      expect(described_class.send(:_fetch_latest, { p_key: 'foo' })).to eql(dmp['dmp'])
    end
  end
end
