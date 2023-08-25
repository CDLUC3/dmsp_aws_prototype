# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Creator' do
  let!(:described_class) { Uc3DmpId::Creator }
  let!(:creator_error) { Uc3DmpId::CreatorError }

  let!(:client) { mock_uc3_dmp_dynamo(dmp: dmp) }
  let!(:publisher) { mock_uc3_dmp_event_bridge }

  let!(:owner) { JSON.parse({ PK: 'PROVENANCE#foo', SK: 'PROFILE' }.to_json) }

  let!(:p_key) { "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{mock_dmp_id}" }

  let!(:dmp) { mock_dmp }

  before do
    ENV['DMP_ID_SHOULDER'] = '11.22222/33'
    ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
  end

  describe 'create(provenance:, json:, logger: nil)' do
    it 'raises a CreatorError if the `DMP_ID_SHOULDER` ENV variable is not defined' do
      ENV.delete('DMP_ID_SHOULDER')
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if the `DMP_ID_BASE_URL` ENV variable is not defined' do
      ENV.delete('DMP_ID_BASE_URL')
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if the :provenance is not a Hash' do
      expect { described_class.create(provenance: 123, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if the :provenance does not contain a :PK' do
      owner.delete('PK')
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if the Uc3DmpId::Validator returns errors' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return(['foo'])
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if the Uc3DmpId::Finder finds a matching :dmp_id' do
      dmp['dmp']['dmp_id'] = 'https://dx.doi.org/11.1234/A1B2c3'
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(true)
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if unable to generate the :PK' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(nil)
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'raises a CreatorError if Dynamo could not save the DMP ID record' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(p_key)
      allow(Uc3DmpId::Helper).to receive(:annotate_dmp_json).and_return(dmp)
      allow(client).to receive(:put_item).and_return(nil)
      expect { described_class.create(provenance: owner, json: dmp) }.to raise_error(creator_error)
    end

    it 'creates the new DMP ID' do
      allow(Uc3DmpId::Validator).to receive(:validate).and_return([])
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(false)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(p_key)
      allow(Uc3DmpId::Helper).to receive(:annotate_dmp_json).and_return(dmp)
      allow(client).to receive(:put_item).and_return(dmp)
      allow(described_class).to receive(:_post_process).and_return(true)

      now = Time.now.utc.iso8601
      result = described_class.create(provenance: owner, json: dmp)
      expect(result['dmp']['created'] >= now).to be(true)
      expect(result['dmp']['modified'] >= now).to be(true)
    end
  end

  describe '_preregister_dmp_id(client:, provenance:, json:, logger: nil)' do
    it 'returns the DMP ID sent in by the provenance system if the provenance is Seeding with live DMPs' do
      owner['seedingWithLiveDmpIds'] = true
      dmp['dmp']['dmproadmap_external_system_identifier'] = 'http://doi.org/SEEDING-ID'

      result = described_class.send(:_preregister_dmp_id, client: client, provenance: owner, json: dmp)
      expect(result).to eql('doi.org/SEEDING-ID')
    end

    it 'raises a CreatorError if a unique DMP ID could not be generated after 10 attempts' do
      owner['seedingWithLiveDmpIds'] = false
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(true)
      expect do
        described_class.send(:_preregister_dmp_id, client: client, provenance: owner,
                                                   json: dmp)
      end.to raise_error(creator_error)
    end

    it 'returns a new DMP ID' do
      owner['seedingWithLiveDmpIds'] = false
      allow(Uc3DmpId::Finder).to receive(:exists?).and_return(false)
      result = described_class.send(:_preregister_dmp_id, client: client, provenance: owner, json: dmp)

      expected_prefix = "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{ENV['DMP_ID_BASE_URL'].gsub(%r{https?://}, '')}"
      expect(result.start_with?(expected_prefix)).to be(true)
      suffix = result.gsub(expected_prefix, '')
      expect(suffix =~ Uc3DmpId::Helper::DOI_REGEX).to be(1)
      expect(suffix.start_with?("/#{ENV.fetch('DMP_ID_SHOULDER', nil)}")).to be(true)
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
        source: 'DmpCreator',
        event_type: 'EZID update',
        logger: nil
      }
      expect(publisher).to have_received(:publish).once.with(expected)
    end

    it 'does not publish a `Citation Fetch` event to EventBridge if there are no citable identifiers' do
      allow(Uc3DmpId::Helper).to receive(:citable_related_identifiers).and_return([])
      described_class.send(:_post_process, json: dmp['dmp'])
      expect(publisher).to have_received(:publish).once
    end

    it 'publishes an `Citation Fetch` event to EventBridge if there are citable identifiers' do
      ids = JSON.parse([{ work_type: 'dataset', descriptor: 'references', type: 'other', identifier: 'foo' }].to_json)
      allow(Uc3DmpId::Helper).to receive(:citable_related_identifiers).and_return(ids)
      described_class.send(:_post_process, json: dmp['dmp'])
      expected = {
        dmp: dmp['dmp'],
        detail: { PK: dmp['dmp']['PK'], SK: dmp['dmp']['SK'], dmproadmap_related_identifiers: ids },
        source: 'DmpCreator',
        event_type: 'Citation Fetch',
        logger: nil
      }
      expect(publisher).to have_received(:publish).once.with(expected)
    end
  end
end
