# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe 'Uc3DmpId::Updater' do
  let!(:described_class) { Uc3DmpId::Updater }
  let!(:updater_error) { Uc3DmpId::UpdaterError }

  let!(:client) { mock_uc3_dmp_dynamo(dmp: dmp) }
  let!(:publisher) { mock_uc3_dmp_event_bridge }

  let!(:owner) { JSON.parse({ PK: 'PROVENANCE#foo', SK: 'PROFILE', name: 'foo' }.to_json) }
  let!(:updater) { JSON.parse({ PK: 'PROVENANCE#bar', SK: 'PROFILE', name: 'bar' }.to_json) }

  let!(:p_key) { "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{mock_dmp_id}" }

  let!(:dmp) do
    record = mock_dmp
    record['dmp']['PK'] = p_key
    record['dmp']['SK'] = Uc3DmpId::Helper::DMP_LATEST_VERSION
    record['dmp']['dmphub_provenance_id'] = owner['PK']
    record
  end

  let!(:transferable_keys) do
    dmp['dmp'].keys.select do |key|
      %w[PK SK].include?(key) || (key.start_with?('dmphub_') && !%w[dmphub_modifications dmphub_versions].include?(key))
    end
  end
  let!(:mods) do
    record = mock_dmp
    transferable_keys.each { |key| record['dmp'].delete(key) }
    record['dmp']['dmp_id'] =
      JSON.parse({ type: 'doi', identifier: Uc3DmpId::Helper.pk_to_dmp_id(p_key: p_key) }.to_json)
    record['dmp']['description'] = 'Lorem ipsum ... TESTING'
    record
  end

  before do
    ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
  end

  describe 'update(provenance:, p_key:, json: {}, note: nil, logger: nil)' do
    it 'raises an UpdaterError when :p_key is not a String' do
      expect { described_class.update(provenance: owner, p_key: 123, json: mods) }.to raise_error(updater_error)
    end

    it 'raises an UpdaterError when :updateable? returns errors' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(described_class).to receive(:_updateable?).and_return(['foo'])
      expect { described_class.update(provenance: owner, p_key: p_key, json: mods) }.to raise_error(updater_error)
    end

    it 'raises an UpdaterError (no changes) when :json is equal to the existing DMP ID' do
      allow(described_class).to receive(:updateable?).and_return([])
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:eql?).and_return(true)
      expect { described_class.update(provenance: owner, p_key: p_key, json: dmp) }.to raise_error(updater_error)
    end

    it 'raises an UpdaterError when Versioner.generate_version returns a nil' do
      allow(described_class).to receive(:updateable?).and_return([])
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:eql?).and_return(false)
      allow(Uc3DmpId::Versioner).to receive(:generate_version).and_return(nil)
      expect { described_class.update(provenance: owner, p_key: p_key, json: mods) }.to raise_error(updater_error)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'saves the changes as the new latest version' do
      allow(described_class).to receive(:updateable?).and_return([])
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp['dmp'])
      allow(Uc3DmpId::Helper).to receive(:eql?).and_return(false)
      allow(Uc3DmpId::Versioner).to receive(:generate_version).and_return(mods['dmp'])
      allow(described_class).to receive(:_process_modifications).and_return(mods['dmp'])
      allow(client).to receive(:put_item).and_return(mods['dmp'])
      allow(described_class).to receive(:_post_process)

      now = Time.now.utc.iso8601
      result = described_class.update(provenance: owner, p_key: p_key, json: mods)
      expect(result['dmp']['dmphub_versions']).to be_nil
      expect(result['dmp']['modified'] >= now).to be(true)

      expect(described_class).to have_received(:_process_modifications).once
      allow(client).to receive(:put_item).once
      expect(described_class).to have_received(:_post_process).once
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe 'attach_narrative(provenance:, p_key:, url:, logger: nil)' do
    let!(:url) { 'http://download.me/narrative.pdf ' }

    it 'raises an UpdaterError when :p_key is not a String' do
      expect { described_class.attach_narrative(provenance: owner, p_key: 123, url: url) }.to raise_error(updater_error)
    end

    it 'raises an UpdaterError when :provenance is not a Hash' do
      expect do
        described_class.attach_narrative(provenance: owner['PK'], p_key: p_key, url: url)
      end.to raise_error(updater_error)
    end

    it 'raises an UpdaterError when :provenance does not contain a :PK' do
      owner.delete('PK')
      expect do
        described_class.attach_narrative(provenance: owner, p_key: p_key, url: url)
      end.to raise_error(updater_error)
    end

    it 'raises an UpdaterError when :provenance does not match the :dmphub_provenance_id of the DMP ID' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      expect do
        described_class.attach_narrative(provenance: updater, p_key: p_key, url: url)
      end.to raise_error(updater_error)
    end

    it 'raises an UpdaterError if the Uc3DmpDynamo::Client is unable to save the change' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:annotate_dmp_json).and_return(dmp['dmp'])
      allow(client).to receive(:put_item).and_return(nil)
      expect do
        described_class.attach_narrative(provenance: owner, p_key: p_key, url: url)
      end.to raise_error(updater_error)
    end

    it 'adds the uploaded PDF\'s access :url to the DMP ID\'s :dmproadmap_related_identifiers' do
      allow(Uc3DmpId::Finder).to receive(:by_pk).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:annotate_dmp_json).and_return(dmp['dmp'])
      allow(client).to receive(:put_item).and_return(dmp['dmp'])
      described_class.attach_narrative(provenance: owner, p_key: p_key, url: url)

      expected = dmp['dmp'].dup
      expected['dmproadmap_related_identifiers'] << JSON.parse({
        work_type: 'output_management_plan', descriptor: 'is_metadata_for', type: 'url', identifier: url
      }.to_json)
      expect(client).to have_received(:put_item).with({ json: expected, logger: nil })
    end
  end

  describe '_updateable?(provenance:, p_key:, latest_version: {}, mods: {})' do
    it 'returns validation errors if the Validator.validate failed' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return(%w[foo bar])
      result = described_class.send(:_updateable?, provenance: updater, p_key: p_key, latest_version: dmp['dmp'],
                                                   mods: mods['dmp'])
      expect(result).to eql('foo, bar')
    end

    it 'returns a Forbidden message if the :provenance is not a Hash' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      result = described_class.send(:_updateable?, provenance: updater['PK'], p_key: p_key, latest_version: dmp['dmp'],
                                                   mods: mods['dmp'])
      expect(result).to eql([Uc3DmpId::Helper::MSG_DMP_FORBIDDEN])
    end

    it 'returns a Forbidden message if the :provenance does not have a :PK' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      updater.delete('PK')
      result = described_class.send(:_updateable?, provenance: updater, p_key: p_key, latest_version: dmp['dmp'],
                                                   mods: mods['dmp'])
      expect(result).to eql([Uc3DmpId::Helper::MSG_DMP_FORBIDDEN])
    end

    it 'returns a Forbidden message if the mod\'s :dmp_id does not match the :p_key' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      mods['dmp'].delete('dmp_id')
      result = described_class.send(:_updateable?, provenance: updater, p_key: p_key, latest_version: dmp['dmp'],
                                                   mods: mods['dmp'])
      expect(result).to eql([Uc3DmpId::Helper::MSG_DMP_FORBIDDEN])
    end

    it 'returns a Not Found message if the :latest_version is not a Hash' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      result = described_class.send(:_updateable?, provenance: updater, p_key: p_key, latest_version: 123,
                                                   mods: mods['dmp'])
      expect(result).to eql([Uc3DmpId::Helper::MSG_DMP_UNKNOWN])
    end

    it 'returns a Not Found message if the :latest_version\'s :PK does not match the :p_key' do
      dmp['dmp']['PK'] = "#{Uc3DmpId::Helper::PK_DMP_PREFIX}testing9876"
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      result = described_class.send(:_updateable?, provenance: updater, p_key: p_key, latest_version: dmp['dmp'],
                                                   mods: mods['dmp'])
      expect(result).to eql([Uc3DmpId::Helper::MSG_DMP_UNKNOWN])
    end
  end

  describe '_process_modifications(owner:, updater:, version:, mods:, note: nil, logger: nil)' do
    it 'returns :version if :mods is not a Hash' do
      result = described_class.send(:_process_modifications, owner: owner, updater: updater, version: dmp, mods: 123)
      expect(result).to eql(dmp)
    end

    it 'returns :version if :updater is nil' do
      result = described_class.send(:_process_modifications, owner: owner, updater: nil, version: dmp, mods: mods)
      expect(result).to eql(dmp)
    end

    it 'returns :mods if :version is not a Hash' do
      result = described_class.send(:_process_modifications, owner: owner, updater: updater, version: 123, mods: mods)
      expect(result).to eql(mods)
    end

    it 'returns :mods if :owner is nil' do
      result = described_class.send(:_process_modifications, owner: nil, updater: updater, version: dmp, mods: mods)
      expect(result).to eql(mods)
    end

    it 'calls Asserter.splice if the updater is the owner' do
      allow(described_class).to receive(:_merge_versions)
      allow(Uc3DmpId::Asserter).to receive(:splice)
      allow(Uc3DmpId::Asserter).to receive(:add)
      described_class.send(:_process_modifications, owner: owner, updater: owner, version: dmp, mods: mods)
      expect(Uc3DmpId::Asserter).to have_received(:splice).once
      expect(Uc3DmpId::Asserter).not_to have_received(:add)
    end

    it 'calls Asserter.add if the updater is NOT the owner' do
      allow(described_class).to receive(:_merge_versions)
      allow(Uc3DmpId::Asserter).to receive(:splice)
      allow(Uc3DmpId::Asserter).to receive(:add)
      described_class.send(:_process_modifications, owner: owner, updater: updater, version: dmp, mods: mods)
      expect(Uc3DmpId::Asserter).not_to have_received(:splice)
      expect(Uc3DmpId::Asserter).to have_received(:add).once
    end
  end

  describe '_merge_versions(latest_version:, mods:, logger: nil)' do
    it 'returns the :mods as-is if :latest_version if not a Hash' do
      expect(described_class.send(:_merge_versions, latest_version: 123, mods: mods)).to eql(mods)
    end

    it 'returns the :mods as-is if :latest_version does not have a :PK and :SK' do
      dmp['dmp'].delete('PK')
      expect(described_class.send(:_merge_versions, latest_version: dmp['dmp'], mods: mods)).to eql(mods)
    end

    it 'adds the attributes from the :latest_version to the :mods' do
      expected = mods
      transferable_keys.each { |key| expected[key] = dmp['dmp'][key] }
      expect(described_class.send(:_merge_versions, latest_version: dmp['dmp'], mods: mods)).to eql(expected)
    end
  end

  describe '_post_process(provenance:, json:, logger: nil)' do
    it 'returns false unless :json is a Hash' do
      expect(described_class.send(:_post_process, provenance: owner, json: 123)).to be(false)
    end

    it 'returns false unless :json contains :dmphub_provenance_id' do
      dmp['dmp'].delete('dmphub_provenance_id')
      expect(described_class.send(:_post_process, provenance: owner, json: dmp['dmp'])).to be(false)
    end

    it 'returns false unless :provenance is a Hash' do
      expect(described_class.send(:_post_process, provenance: 123, json: dmp['dmp'])).to be(false)
    end

    it 'returns false unless :provenance contains :PK' do
      owner.delete('PK')
      expect(described_class.send(:_post_process, provenance: owner, json: dmp['dmp'])).to be(false)
    end

    it 'doesn\'t publish an `EZID update` event to EventBridge if the owner of the DMP ID is NOT the updater' do
      described_class.send(:_post_process, provenance: updater, json: dmp['dmp'])
      expect(publisher).not_to have_received(:publish)
    end

    it 'publishes an `EZID update` event to EventBridge if the owner of the DMP ID is the one making the update' do
      described_class.send(:_post_process, provenance: owner, json: dmp['dmp'])
      expected = {
        dmp: dmp['dmp'],
        source: 'DmpUpdater',
        event_type: 'EZID update',
        logger: nil
      }
      expect(publisher).to have_received(:publish).once.with(expected)
    end

    it 'does not send a `Citation Fetch` event if the owner of the DMP ID is NOT the one making the update' do
      allow(Uc3DmpId::Helper).to receive(:citable_related_identifiers).and_return([])
      described_class.send(:_post_process, provenance: updater, json: dmp['dmp'])
      expect(publisher).not_to have_received(:publish)
    end

    it 'does not publish a `Citation Fetch` event to EventBridge if there are no citable identifiers' do
      allow(Uc3DmpId::Helper).to receive(:citable_related_identifiers).and_return([])
      described_class.send(:_post_process, provenance: owner, json: dmp['dmp'])
      expect(publisher).to have_received(:publish).once
    end

    it 'publishes an `Citation Fetch` event to EventBridge if there are citable identifiers' do
      ids = JSON.parse([{ work_type: 'dataset', descriptor: 'references', type: 'other', identifier: 'foo' }].to_json)
      allow(Uc3DmpId::Helper).to receive(:citable_related_identifiers).and_return(ids)
      described_class.send(:_post_process, provenance: owner, json: dmp['dmp'])
      expected = {
        dmp: dmp['dmp'],
        detail: { PK: dmp['dmp']['PK'], SK: dmp['dmp']['SK'], dmproadmap_related_identifiers: ids },
        source: 'DmpUpdater',
        event_type: 'Citation Fetch',
        logger: nil
      }
      expect(publisher).to have_received(:publish).once.with(expected)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
