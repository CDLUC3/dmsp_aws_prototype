# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'KeyHelper' do
  let!(:described_class) { KeyHelper }

  before do
    allow(SsmReader).to receive(:log_error).and_return(true)
  end

  describe 'dmp_id_base_url' do
    it 'returns the environment variable value as is if it ends with "/"' do
      mock_ssm(value: 'https://foo.org/')
      expect(described_class.dmp_id_base_url).to eql('https://foo.org/')
    end

    it 'appends a "/" to the environment variable value if does not ends with it' do
      mock_ssm(value: 'https://foo.org')
      expect(described_class.dmp_id_base_url).to eql('https://foo.org/')
    end
  end

  describe 'api_base_url' do
    it 'returns the environment variable value as is if it ends with "/"' do
      mock_ssm(value: 'https://foo.org/')
      expect(described_class.api_base_url).to eql('https://foo.org/')
    end

    it 'appends a "/" to the environment variable value if does not ends with it' do
      mock_ssm(value: 'https://foo.org')
      expect(described_class.api_base_url).to eql('https://foo.org/')
    end
  end

  describe 'format_dmp_id(value:, with_protocol:)' do
    let!(:dmp_id_prefix) { 'foo.org/99.88888/' }

    before do
      mock_ssm(value: 'https://foo.org')
    end

    it 'returns nil if :value does not match the DOI_REGEX' do
      expect(described_class.format_dmp_id(value: '00000')).to be_nil
    end

    it 'ignores "doi:" in the :value' do
      expected = "#{dmp_id_prefix}777.66/555"
      expect(described_class.format_dmp_id(value: 'doi:99.88888/777.66/555')).to eql(expected)
    end

    it 'includes the url protocol if specified to do so' do
      expected = "https://#{dmp_id_prefix}123456"
      expect(described_class.format_dmp_id(value: '99.88888/123456', with_protocol: true)).to eql(expected)
    end

    it 'ignores preceding "/" character in the :value' do
      expected = "#{dmp_id_prefix}777.66/555"
      expect(described_class.format_dmp_id(value: '/99.88888/777.66/555')).to eql(expected)
    end

    it 'does not replace a predefined domain name with the DMP_ID_BASE_URL if the value is a URL' do
      expected = 'https://bar.org/99.88888/777.66/555'
      expect(described_class.format_dmp_id(value: expected)).to eql(expected)
    end

    it 'handles variations of DOI format' do
      %w[zzzzzz zzz.zzz zzz/zzz zzz-zzz zzz_zzz].each do |id|
        expected = "#{dmp_id_prefix}#{id}"
        expect(described_class.format_dmp_id(value: expected)).to eql(expected)
      end
    end
  end

  describe 'dmp_id_to_pk(json:)' do
    before do
      mock_ssm(value: 'https://foo.org')
    end

    it 'returns nil if :json is not a Hash' do
      expect(described_class.dmp_id_to_pk(json: nil)).to be_nil
    end

    it 'returns nil if :json has no :identifier' do
      json = JSON.parse({ type: 'doi' }.to_json)
      expect(described_class.dmp_id_to_pk(json: json)).to be_nil
    end

    it 'correctly formats a DOI' do
      expected = 'DMP#foo.org/99.88888/77776666.555'
      json = JSON.parse({ type: 'other', identifier: '99.88888/77776666.555' }.to_json)
      expect(described_class.dmp_id_to_pk(json: json)).to eql(expected)
      json = JSON.parse({ type: 'doi', identifier: 'doi:99.88888/77776666.555' }.to_json)
      expect(described_class.dmp_id_to_pk(json: json)).to eql(expected)
      json = JSON.parse({ type: 'url', identifier: expected }.to_json)
      expect(described_class.dmp_id_to_pk(json: json)).to eql(expected)
    end

    it 'returns nil if the dmp_id was NOT a valid DOI' do
      json = JSON.parse({ type: 'doi', identifier: '99999' }.to_json)
      expect(described_class.dmp_id_to_pk(json: json)).to be_nil
    end
  end

  describe 'path_parameter_to_pk(param:)' do
    let!(:base_url) { 'https://example.com/' }

    before do
      allow(described_class).to receive(:dmp_id_base_url).and_return(base_url)
    end

    it 'returns nil if :param is not a String' do
      expect(described_class.path_parameter_to_pk(param: 123)).to be_nil
    end

    it 'returns nil if :param is an empty String' do
      expect(described_class.path_parameter_to_pk(param: '  ')).to be_nil
    end

    it 'retains the DMP ID base url if it is part of the :param' do
      param = "#{base_url}10.12345/abc123"
      result = described_class.path_parameter_to_pk(param: param)
      expect(result).to eql("#{KeyHelper::PK_DMP_PREFIX}#{param.gsub('https://', '')}")
    end

    it 'unescapes the DMP ID' do
      param = "#{base_url}doi:10.12345%2Fabc123"
      result = described_class.path_parameter_to_pk(param: param)
      expected = "#{KeyHelper::PK_DMP_PREFIX}#{param.gsub('https://', '').gsub('%2F', '/')}"
      expect(result).to eql(expected)

      param = "#{base_url}10.12345%2Fabc123"
      result = described_class.path_parameter_to_pk(param: param)
      expected = "#{KeyHelper::PK_DMP_PREFIX}#{param.gsub('https://', '').gsub('%2F', '/')}"
      expect(result).to eql(expected)

      param = "#{base_url}10.12345%2Fabc123"
      result = described_class.path_parameter_to_pk(param: param)
      expected = "#{KeyHelper::PK_DMP_PREFIX}#{param.gsub('https://', '').gsub('%2F', '/')}"
      expect(result).to eql(expected)
    end

    it 'appends the DMP ID base url if necessary' do
      param = '10.12345/abc123'
      result = described_class.path_parameter_to_pk(param: param)
      expect(result).to eql("#{KeyHelper::PK_DMP_PREFIX}#{base_url.gsub('https://', '')}#{param}")
    end
  end

  describe 'pk_to_dmp_id(p_key:)' do
    it 'removes the PK prefix if applicable' do
      mock_ssm(value: 'https://foo.org/')
      expected = { type: 'doi', identifier: 'https://foo.org/10.12345/12' }
      expect(described_class.pk_to_dmp_id(p_key: 'DMP#10.12345/12')).to eql(expected)
      dmp_id = 'https://foo.org/99.88888/777666.555/444'
      expected = { type: 'doi', identifier: dmp_id }
      expect(described_class.pk_to_dmp_id(p_key: "DMP##{dmp_id}")).to eql(expected)
      expected = { type: 'doi', identifier: 'https://foo.org/99.98765/98' }
      expect(described_class.pk_to_dmp_id(p_key: '99.98765/98')).to eql(expected)
    end
  end

  describe 'format_provenance_id(provenance:, value:)' do
    let!(:provenance) do
      JSON.parse({
        PK: "#{described_class::PK_PROVENANCE_PREFIX}example",
        SK: described_class::SK_PROVENANCE_PREFIX,
        homepage: 'https://example.com',
        redirectUri: 'https://example.com/api/dmps/callback'
      }.to_json)
    end

    it 'returns value as-is if :provenance is nil' do
      expect(described_class.format_provenance_id(provenance: nil, value: 'foo')).to eql('foo')
    end

    it 'returns value as-is if :value is a DOI (full URL, e.g. https://doi.org/10.12345/abcd)' do
      doi = 'https://doi.org/10.12345/AbC123'
      expect(described_class.format_provenance_id(provenance: provenance, value: doi)).to eql(doi)
    end

    it 'appends the provenance PK id to a DOI (NOT full URL, e.g. 10.12345/abcd)' do
      doi = '10.12345/ABC123'
      expect(described_class.format_provenance_id(provenance: provenance, value: doi)).to eql("example##{doi.downcase}")
    end

    it 'removes the provenance :homepage from the :value' do
      value = "#{provenance['homepage']}/foo"
      expect(described_class.format_provenance_id(provenance: provenance, value: value)).to eql('example#foo')
    end

    it 'removes the provenance :redirectUri from the :value' do
      value = "#{provenance['callbackUri']}/foo"
      expect(described_class.format_provenance_id(provenance: provenance, value: value)).to eql('example#foo')
    end

    it 'appends the provenance PK id to the :value' do
      expect(described_class.format_provenance_id(provenance: provenance, value: 'foo123')).to eql('example#foo123')
    end
  end

  describe 'append_pk_prefix(dmp:, provenance:)' do
    it 'returns nil if no :dmp or :provenance is defined' do
      expect(described_class.append_pk_prefix).to be_nil
    end

    it 'returns nil if both the :dmp and :provenance are defined' do
      expect(described_class.append_pk_prefix(dmp: 'foo', provenance: 'foo')).to be_nil
    end

    it 'appends the :PK prefix to the :dmp' do
      expected = "#{described_class::PK_DMP_PREFIX}foo"
      expect(described_class.append_pk_prefix(dmp: 'foo')).to eql(expected)
    end

    it 'appends the :PK prefix to the :provenance' do
      expected = "#{described_class::PK_PROVENANCE_PREFIX}foo"
      expect(described_class.append_pk_prefix(provenance: 'foo')).to eql(expected)
    end
  end

  describe 'remove_pk_prefix(dmp:, provenance:)' do
    it 'returns nil if no :dmp or :provenance is defined' do
      expect(described_class.remove_pk_prefix).to be_nil
    end

    it 'returns nil if both the :dmp and :provenance are defined' do
      expect(described_class.remove_pk_prefix(dmp: 'foo', provenance: 'foo')).to be_nil
    end

    it 'removes the :PK prefix from the :dmp' do
      dmp = "#{described_class::PK_DMP_PREFIX}foo"
      expect(described_class.remove_pk_prefix(dmp: dmp)).to eql('foo')
    end

    it 'removes the :PK prefix from the :provenance' do
      prov = "#{described_class::PK_PROVENANCE_PREFIX}foo"
      expect(described_class.remove_pk_prefix(provenance: prov)).to eql('foo')
    end
  end
end
