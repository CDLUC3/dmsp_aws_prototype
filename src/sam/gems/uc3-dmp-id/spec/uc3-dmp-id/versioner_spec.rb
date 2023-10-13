# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Versioner' do
  let!(:described_class) { Uc3DmpId::Versioner }

  let!(:p_key) { "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{mock_dmp_id}" }
  let!(:landing_page_url) { 'http://foo.bar/dmps/' }

  before do
    mock_uc3_dmp_dynamo
    ENV['DMP_ID_BASE_URL'] = 'http://doi.org'
    ENV['DMP_ID_LANDING_URL'] = landing_page_url
  end

  describe 'get_versions(p_key:, client: nil, logger: nil)' do
    it 'returns an empty array if p_key is not a valid String' do
      expect(described_class.get_versions(p_key: 123)).to eql([])
    end

    it 'fetches the :modified dates for each Dyanmo table entry for the PK' do
      expect(described_class.get_versions(p_key:)).to eql([mock_dmp])
    end
  end

  describe 'generate_version(client:, latest_version:, owner:, updater:, logger: nil)' do
    let!(:client) { mock_uc3_dmp_dynamo }
    let!(:owner) { 'PROVENANCE#foo' }

    it 'returns the :latest_version as-is if it could not determine the modified time' do
      dmp = JSON.parse({ modified: '123A' }.to_json)
      expect(described_class.generate_version(client:, latest_version: dmp, owner:,
                                              updater: owner)).to eql(dmp)
    end

    it 'returns the :latest_version as-is if the owner of the DMP ID does not match the updater' do
      dmp = JSON.parse({ modified: (Time.now.utc - 7200).utc.iso8601 }.to_json)
      updater = 'PROVENANCE#bar'
      expect(described_class.generate_version(client:, latest_version: dmp, owner:,
                                              updater:)).to eql(dmp)
    end

    it 'returns the :latest_version as-is if the modified time of the latest version is within the past hour' do
      dmp = JSON.parse({ modified: Time.now.utc.iso8601 }.to_json)
      expect(described_class.generate_version(client:, latest_version: dmp, owner:,
                                              updater: owner)).to eql(dmp)
    end

    it 'returns nil if it was unable to generate a version snapshot' do
      allow(client).to receive(:put_item).and_return(nil)
      dmp = JSON.parse({ modified: (Time.now.utc - 72_000).utc.iso8601 }.to_json)
      expect(described_class.generate_version(client:, latest_version: dmp, owner:,
                                              updater: owner)).to be_nil
    end

    it 'generates the version snapshot and returns the :latest_version' do
      tstamp = (Time.now.utc - 72_000).utc.iso8601
      dmp = JSON.parse({ modified: tstamp }.to_json)
      version = JSON.parse({ SK: "#{Uc3DmpId::Helper::SK_DMP_PREFIX}#{tstamp}", modified: tstamp }.to_json)
      expect(described_class.generate_version(client:, latest_version: dmp, owner:,
                                              updater: owner)).to eql(dmp)
      expect(client).to have_received(:put_item).with(json: version, logger: nil).once
    end
  end

  describe 'append_versions(p_key:, dmp:, client: nil, logger: nil)' do
    let!(:first_version) { JSON.parse({ modified: '2023-01-18T13:14:15Z' }.to_json) }
    let!(:last_version) { JSON.parse({ modified: '2023-07-21T22:23:24Z' }.to_json) }

    let!(:dmp) { JSON.parse({ dmp: { title: 'Foo bar' } }.to_json) }

    it 'returns the :json as-is if the :p_key is not a valid String' do
      expect(described_class.append_versions(p_key: 123, dmp:)).to eql(dmp)
    end

    it 'returns the :json as-is if :json is not a Hash' do
      expect(described_class.append_versions(p_key:, dmp: '123')).to be(123)
    end

    it 'returns the :json as-is if :json does not have a top level :dmp' do
      json = JSON.parse({ title: 'Foo' }.to_json)
      result = described_class.append_versions(p_key:, dmp: json)
      expect(assert_dmps_match(obj_a: result, obj_b: json, debug: false)).to be(true)
    end

    it 'does NOT append the :dmphub_versions Array if there is only one version' do
      allow(described_class).to receive(:get_versions).and_return([first_version])
      result = described_class.append_versions(p_key:, dmp:)
      expect(assert_dmps_match(obj_a: result, obj_b: dmp, debug: false)).to be(true)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'appends the :dmphub_versions Array if there are multiple versions of the DMP ID' do
      allow(described_class).to receive(:get_versions).and_return([first_version, last_version])
      result = described_class.append_versions(p_key:, dmp:)
      pk = Uc3DmpId::Helper.remove_pk_prefix(p_key:)
      expected = JSON.parse({
        dmp: {
          title: 'Foo bar',
          dmphub_versions: [
            { timestamp: first_version['modified'],
              url: "#{landing_page_url}#{pk}?version=#{first_version['modified']}" },
            { timestamp: last_version['modified'],
              url: "#{landing_page_url}#{pk}?version=#{last_version['modified']}" }
          ]
        }
      }.to_json)
      expect(assert_dmps_match(obj_a: result, obj_b: expected, debug: false)).to be(true)
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
