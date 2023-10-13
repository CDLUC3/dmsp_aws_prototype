# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpProvenance::Helper' do
  let!(:described_class) { Uc3DmpProvenance::Helper }
  let!(:client_err) { Uc3DmpCognito::ClientError }

  describe 'append_pk_prefix(provenance:)' do
    it 'returns nil if :provenance is nil' do
      expect(described_class.append_pk_prefix(provenance: nil)).to be_nil
    end

    it 'returns nil if :provenance is an empty string' do
      expect(described_class.append_pk_prefix(provenance: nil)).to be_nil
    end

    it 'prepands the prefix to the :provenance value' do
      expected = "#{Uc3DmpProvenance::Helper::PK_PROVENANCE_PREFIX}foo"
      expect(described_class.append_pk_prefix(provenance: 'foo')).to eql(expected)
    end
  end

  describe 'remove_pk_prefix(provenance:)' do
    it 'returns nil if :provenance is nil' do
      expect(described_class.remove_pk_prefix(provenance: nil)).to be_nil
    end

    it 'returns nil if :provenance is an empty string' do
      expect(described_class.remove_pk_prefix(provenance: nil)).to be_nil
    end

    it 'returns the value as-is if it does not contain the prefix' do
      expect(described_class.remove_pk_prefix(provenance: 'foo')).to eql('foo')
    end

    it 'prepands the prefix to the :provenance value' do
      prov = "#{Uc3DmpProvenance::Helper::SK_PROVENANCE_PREFIX}foo"
      expect(described_class.remove_pk_prefix(provenance: 'foo')).to eql('foo')
    end
  end

  describe 'format_provenance_callback_url(provenance:, value:)' do
    let!(:dmp_id) { mock_dmp_id }
    let!(:prov) { JSON.parse({ homepage: 'http://example.com/api' }.to_json) }

    it 'returns :value as-is if no :provenance was provided' do
      expect(described_class.format_provenance_callback_url(provenance: nil, value: dmp_id)).to eql(dmp_id)
    end

    it 'strips off the protocol' do
      val = 'http://foo.bar/123'
      expected = 'foo.bar/123'
      expect(described_class.format_provenance_callback_url(provenance: prov, value: val)).to eql(expected)
    end

    it 'returns :value as-is if :provenance does not contain a :homepage or :callbackUri' do
      provenance = JSON.parse({ foo: 'bar' }.to_json)
      expect(described_class.format_provenance_callback_url(provenance:, value: dmp_id)).to eql(dmp_id)
    end

    it 'removes the provenance homepage' do
      val = 'http://example.com/api/123'
      expected = '123'
      expect(described_class.format_provenance_callback_url(provenance: prov, value: val)).to eql(expected)
    end

    it 'returns the expected url' do
      expected = "#{mock_url}#{dmp_id}"
      expect(described_class.format_provenance_callback_url(provenance: prov, value: dmp_id)).to eql(dmp_id)
    end
  end
end
