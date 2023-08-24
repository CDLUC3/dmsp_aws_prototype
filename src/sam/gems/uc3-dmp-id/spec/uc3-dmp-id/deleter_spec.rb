# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Deleter' do
  let!(:described_class) { Uc3DmpId::Deleter }
  let!(:deleter_error) { Uc3DmpId::DeleterError }

  let!(:client) { mock_uc3_dmp_dynamo(dmp: dmp) }
  let!(:publisher) { mock_uc3_dmp_event_bridge }

  let!(:owner) { JSON.parse({ PK: 'PROVENANCE#foo', SK: 'PROFILE' }.to_json) }
  let!(:updater) { JSON.parse({ PK: 'PROVENANCE#bar', SK: 'PROFILE' }.to_json) }

  let!(:p_key) { "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{mock_dmp_id}" }

  let!(:dmp) do
    record = mock_dmp
    record['dmp']['PK'] = p_key
    record['dmp']['SK'] = Uc3DmpId::Helper::DMP_LATEST_VERSION
    record['dmp']['dmphub_provenance_id'] = owner['PK']
    record
  end

  before do
    ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
  end

  describe 'tombstone(provenance:, p_key:, logger: nil)' do
    it 'raises an DeleterError when :p_key is not a String' do
      expect { described_class.tombstone(provenance: owner, p_key: 123) }.to raise_error(deleter_error)
    end

    it 'raises an DeleterError when :provenance is not a Hash' do
      expect { described_class.tombstone(provenance: 123, p_key: p_key) }.to raise_error(deleter_error)
    end

    it 'raises an DeleterError when :provenance does not have a :PK' do
      owner.delete('PK')
      expect { described_class.tombstone(provenance: owner, p_key: p_key) }.to raise_error(deleter_error)
    end

    it 'raises an DeleterError when the DMP ID could not be found' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(nil)
      expect { described_class.tombstone(provenance: owner, p_key: p_key) }.to raise_error(deleter_error)
    end

    it 'raises an DeleterError when :provenance does not match the DMP ID\'s :dmphub_provenance_id' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      expect { described_class.tombstone(provenance: updater, p_key: p_key) }.to raise_error(deleter_error)
    end

    it 'raises an DeleterError when it is not the latest version of the DMP ID' do
      dmp['dmp']['SK'] = "#{Uc3DmpId::Helper::SK_DMP_PREFIX}2020-03-15T11:22:33Z"
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      expect { described_class.tombstone(provenance: owner, p_key: p_key) }.to raise_error(deleter_error)
    end

    it 'tombstones the DMP ID' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(client).to receive(:put_item).and_return(dmp['dmp'])
      allow(client).to receive(:delete_item).and_return(dmp['dmp'])
      allow(described_class).to receive(:_post_process)

      now = Time.now.utc.iso8601
      result = described_class.tombstone(provenance: owner, p_key: p_key)
      expect(result['dmp']['modified'] >= now).to be(true)
      expect(result['dmp']['title'].start_with?('OBSOLETE: ')).to be(true)

      expect(client).to have_received(:put_item).once
      expect(client).to have_received(:delete_item).once
    end
  end

  describe '_post_process(json:, logger: nil)' do
    it 'returns false unless :json is a Hash' do
      expect(described_class.send(:_post_process, json: 123)).to be(false)
    end

    it 'publishes an `EZID update` event to EventBridge if the owner of the DMP ID is the one making the update' do
      described_class.send(:_post_process, json: dmp['dmp'])
      expected = {
        dmp: dmp['dmp'],
        source: 'DmpDeleter',
        event_type: 'EZID update',
        logger: nil
      }
      expect(publisher).to have_received(:publish).once.with(expected)
    end
  end
end
