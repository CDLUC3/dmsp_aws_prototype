# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Helper' do
  let!(:described_class) { Uc3DmpId::Helper }

  describe 'append_pk_prefix(p_key:)' do
    it 'appends the prefix' do
      key = 'foo/bar'
      expect(described_class.append_pk_prefix(p_key: key)).to eql("#{described_class::PK_DMP_PREFIX}#{key}")
    end

    it 'returns the :p_key as is if it already starts with the prefix' do
      key = "#{described_class::PK_DMP_PREFIX}foo/bar"
      expect(described_class.append_pk_prefix(p_key: key)).to eql(key)
    end
  end

  describe 'remove_pk_prefix(p_key:)' do
    it 'returns the :p_key as is if it does not start with the prefix' do
      key = 'foo/bar'
      expect(described_class.remove_pk_prefix(p_key: key)).to eql(key)
    end

    it 'removes the prefix' do
      key = "foo/bar"
      expect(described_class.remove_pk_prefix(p_key: "#{described_class::PK_DMP_PREFIX}#{key}")).to eql(key)
    end
  end

  describe 'append_sk_prefix(s_key:)' do
    it 'appends the prefix' do
      key = 'foo/bar'
      expect(described_class.append_sk_prefix(s_key: key)).to eql("#{described_class::SK_DMP_PREFIX}#{key}")
    end

    it 'returns the :s_key as is if it already starts with the prefix' do
      key = "#{described_class::SK_DMP_PREFIX}foo/bar"
      expect(described_class.append_sk_prefix(s_key: key)).to eql(key)
    end
  end

  describe 'remove_sk_prefix(s_key:)' do
    it 'returns the :s_key as is if it does not start with the prefix' do
      key = 'foo/bar'
      expect(described_class.remove_sk_prefix(s_key: key)).to eql(key)
    end

    it 'removes the prefix' do
      key = "foo/bar"
      expect(described_class.remove_sk_prefix(s_key: "#{described_class::SK_DMP_PREFIX}#{key}")).to eql(key)
    end
  end

  describe 'dmp_id_base_url' do
    it 'returns the default if no ENV[\'DMP_ID_BASE_URL\'] is defined' do
      ENV.delete('DMP_ID_BASE_URL')
      expect(described_class.dmp_id_base_url).to eql(described_class::DEFAULT_LANDING_PAGE_URL)
    end
    it 'returns the ENV[\'DMP_ID_BASE_URL\']' do
      ENV['DMP_ID_BASE_URL'] = 'http://foo.bar/'
      expect(described_class.dmp_id_base_url).to eql(ENV['DMP_ID_BASE_URL'])
    end
    it 'appends a trailing \'/\' if necessary' do
      ENV['DMP_ID_BASE_URL'] = 'http://foo.bar'
      expect(described_class.dmp_id_base_url).to eql("#{ENV['DMP_ID_BASE_URL']}/")
    end
  end

  describe 'landing_page_url' do
    it 'returns the default if no ENV[\'DMP_ID_LANDING_URL\'] is defined' do
      ENV.delete('DMP_ID_LANDING_URL')
      expect(described_class.landing_page_url).to eql(described_class::DEFAULT_LANDING_PAGE_URL)
    end
    it 'returns the ENV[\'DMP_ID_LANDING_URL\']' do
      ENV['DMP_ID_LANDING_URL'] = 'http://foo.bar/'
      expect(described_class.landing_page_url).to eql(ENV['DMP_ID_LANDING_URL'])
    end
    it 'appends a trailing \'/\' if necessary' do
      ENV['DMP_ID_LANDING_URL'] = 'http://foo.bar'
      expect(described_class.landing_page_url).to eql("#{ENV['DMP_ID_LANDING_URL']}/")
    end
  end

  describe 'format_dmp_id(value:, with_protocol: false)' do
    let!(:dmp_id) { 'doi.org/11.2222/3333.444'}

    before do
      ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
    end

    it 'returns nil if the value is not a DOI' do
      expect(described_class.format_dmp_id(value: 'https://dmptool.org')).to eql(nil)
    end
    it 'removes the protocol from the value by default' do
      val = "#{ENV['DMP_ID_BASE_URL']}/#{dmp_id}"
      expect(described_class.format_dmp_id(value: val)).to eql("doi.org/#{dmp_id}")
    end
    it 'returns the value as is if it starts with a protocol' do
      val = "#{ENV['DMP_ID_BASE_URL']}/#{dmp_id}"
      expect(described_class.format_dmp_id(value: val, with_protocol: true)).to eql(val)
    end
    it 'removes the `doi:` prefix' do
      val = "doi:#{dmp_id}"
      expect(described_class.format_dmp_id(value: val)).to eql(dmp_id)
    end
    it 'removes preceding `/` character' do
      val = "/#{dmp_id}"
      expect(described_class.format_dmp_id(value: val)).to eql(dmp_id)
    end
    it 'does not include the protocol by default' do
      expect(described_class.format_dmp_id(value: dmp_id)).to eql(dmp_id)
    end
    it 'includes the protocol if we specify :with_protocol' do
      expected = "https://#{dmp_id}"
      expect(described_class.format_dmp_id(value: dmp_id, with_protocol: true)).to eql(expected)
    end
  end

  describe 'path_parameter_to_pk(param:)' do
    before do
      ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
    end

    it 'returns nil if param is not a string' do
      expect(described_class.path_parameter_to_pk(param: 123)).to eql(nil)
    end
    it 'handles URI escaped characters' do
      expect(described_class.path_parameter_to_pk(param: 'doi%3A11%2E2222%2F33333')).to eql('DMP#doi.org/11.2222/33333')
    end
    it 'replaces a domain with our base domain' do
      expect(described_class.path_parameter_to_pk(param: 'doi:foo.bar/11.2222/33333')).to eql('DMP#doi.org/11.2222/33333')
    end
    it 'returns the DMP ID as a PK' do
      expect(described_class.path_parameter_to_pk(param: '11.2222/33333')).to eql('DMP#doi.org/11.2222/33333')
    end
  end

  describe 'dmp_id_to_pk(json:)' do
    it 'returns nil if :json is not a Hash' do
      expect(described_class.dmp_id_to_pk(json: 123)).to eql(nil)
    end
    it 'returns nil if :json does not contain :identifier' do
      expect(described_class.dmp_id_to_pk(json: JSON.parse({ foo: 'bar' }.to_json))).to eql(nil)
    end
    it 'returns nil if :format_dmp_id returns nil' do
      allow(described_class).to receive(:format_dmp_id).and_return(nil)
      expect(described_class.dmp_id_to_pk(json: JSON.parse({ identifier: '11.2222/12345' }.to_json))).to eql(nil)
    end
    it 'formats the PK as expected' do
      val = 'doi.org/11.2222/12345'
      allow(described_class).to receive(:format_dmp_id).and_return(val)
      expect(described_class.dmp_id_to_pk(json: JSON.parse({ identifier: '11.2222/12345' }.to_json))).to eql("DMP##{val}")
    end
  end

  describe 'pk_to_dmp_id(p_key:)' do
    it 'returns nil if :p_key is nil' do
      expect(described_class.pk_to_dmp_id(p_key: nil)).to eql(nil)
    end
    it 'returns the expected Hash' do
      ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
      expected = { type: 'doi', identifier: 'https://doi.org/11.2222.12345'}
      allow(described_class).to receive(:remove_pk_prefix).and_return('doi.org/11.2222.12345')
      allow(described_class).to receive(:format_dmp_id).and_return(expected[:identifier])
      expect(described_class.pk_to_dmp_id(p_key: 'DMP#doi.org/11.2222.12345')).to eql(expected)
    end
  end

  describe 'parse_json(json:)' do
    it 'returns the :json as-is if it is already a Hash' do
      expect(described_class.parse_json(json: { foo: 'bar' })).to eql({ foo: 'bar' })
    end
    it 'returns nil if :json is not a String or Hash' do
      expect(described_class.parse_json(json: 123)).to eql(nil)
    end
    it 'raises a JSON::ParserError if the :json String is invalid' do
      expect { described_class.parse_json(json: 'foo: bar') }.to raise_error(JSON::ParserError)
    end
    it 'parses the String into a Hash' do
      expect(described_class.parse_json(json: '{"foo":"bar"}')).to eql(JSON.parse({ foo: 'bar' }.to_json))
    end
  end

  describe 'eql?(dmp_a:, dmp_b:)' do
    let!(:dmp) do
      now = Time.now.utc.iso8601

      JSON.parse({
        dmp: {
          PK: "#{described_class::PK_DMP_PREFIX}foo",
          SK: described_class::DMP_LATEST_VERSION,
          title: 'Foo bar',
          created: now,
          modified: now,
          dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
          dmphub_versions: [
            { timestamp: now, url: 'http://foo.bar/foo' },
            { timestamp: now, url: 'http://foo.bar/foo?version=2000-01-01T00:00:00+00:00' }
          ]
        }
      }.to_json)
    end

    it 'just compares the 2 values as-is if :dmp_a or :dmp_b is not a Hash' do
      expect(described_class.eql?(dmp_a: 'foo', dmp_b: { dmp: { bar: 'foo' } })).to eql(false)
    end
    it 'just compares the 2 values as-is if :dmp_a or dmp_b does not have a top level :dmp' do
      expect(described_class.eql?(dmp_a: { foo: 'bar' }, dmp_b: { dmp: { bar: 'foo' } })).to eql(false)
    end
    it 'returns true if :dmp_a and :dmp_b are identical' do
      expect(described_class.eql?(dmp_a: dmp, dmp_b: dmp)).to eql(true)
    end
    it 'returns false if :dmp_a PK does not start with the DMP ID :PK prefix' do
      dmp_a = dmp.clone[:PK] = 'FOO'
      expect(described_class.eql?(dmp_a: dmp_a, dmp_b: dmp)).to eql(false)
    end
    it 'returns false if :dmp_b PK does not start with the DMP ID :PK prefix' do
      dmp_b = dmp.clone[:PK] = 'FOO'
      expect(described_class.eql?(dmp_a: dmp, dmp_b: dmp_b)).to eql(false)
    end
    it 'returns false if :dmp_a and :dmp_b :PKs do not match' do
      dmp_a = dmp.clone[:PK] = "#{described_class::PK_DMP_PREFIX}FOO"
      expect(described_class.eql?(dmp_a: dmp_a, dmp_b: dmp)).to eql(false)
    end
    it 'ignores :SK, :created, :modified, :dmphub_modification_day and :dmphub_versions' do
      dmp_a = JSON.parse({
        dmp: {
          PK: "#{described_class::PK_DMP_PREFIX}foo",
          SK: "#{described_class::SK_DMP_PREFIX}2000-01-01T00:00:00+00:00",
          title: 'Foo bar',
          created: '2000-01-01T00:00:00+00:00',
          modified: '2000-01-01T00:00:00+00:00',
          dmphub_modification_day: '2000-01-01',
          dmphub_versions: []
        }
      }.to_json)
      expect(described_class.eql?(dmp_a: dmp_a, dmp_b: dmp)).to eql(true)
    end
  end

  describe 'extract_owner_id(json: {})' do
    let!(:dmp) do
      JSON.parse({
        dmp: {
          PK: "#{described_class::PK_DMP_PREFIX}foo",
          SK: described_class::DMP_LATEST_VERSION,
          contact: {
            contact_id: { type: 'orcid', identifier: 'contact' }
          },
          contributor: [
            { contributor_id: { type: 'orcid', identifier: 'first' } },
            { contributor_id: { type: 'orcid', identifier: 'last' } }
          ]
        }
      }.to_json)
    end

    it 'returns nil if :json is not a Hash' do
      expect(described_class.extract_owner_id(json: 123)).to eql(nil)
    end
    it 'returns the :contact_id if available' do
      expect(described_class.extract_owner_id(json: dmp)).to eql('contact')
    end
    it 'returns the first :contributor_id if :contact_id is not available' do
      dmp['dmp'].delete('contact')
      expect(described_class.extract_owner_id(json: dmp)).to eql('first')
    end
  end

  describe 'extract_owner_org(json: {})' do
    let!(:dmp) do
      JSON.parse({
        dmp: {
          PK: "#{described_class::PK_DMP_PREFIX}foo",
          SK: described_class::DMP_LATEST_VERSION,
          contact: {
            dmproadmap_affiliation: { affiliation_id: { type: 'ror', identifier: 'contact' } }
          },
          contributor: [
            { dmproadmap_affiliation: { affiliation_id: { type: 'ror', identifier: 'first' } } },
            { dmproadmap_affiliation: { affiliation_id: { type: 'ror', identifier: 'last' } } },
            { dmproadmap_affiliation: {affiliation_id:  { type: 'ror', identifier: 'last' } } }
          ]
        }
      }.to_json)
    end

    it 'returns nil if :json is not a Hash' do
      expect(described_class.extract_owner_org(json: 123)).to eql(nil)
    end
    it 'returns the :contact affiliation if available' do
      expect(described_class.extract_owner_org(json: dmp)).to eql('contact')
    end
    it 'returns the most common :contributor affiliation if :contact is not available' do
      dmp['dmp'].delete('contact')
      expect(described_class.extract_owner_org(json: dmp)).to eql('last')
    end
  end

  describe 'annotate_dmp_json(provenance:, p_key:, json:)' do
    let!(:p_key) { 'DMP#doi.org/11.2222/12345' }
    let!(:provenance) { JSON.parse({ PK: 'PROVENANCE#foo', seedingWithLiveDmpIds: false }.to_json) }
    let!(:dmp) do
      JSON.parse({
        title: 'Foo bar'
      }.to_json)
    end

    before do
      ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
      allow(described_class).to receive(:extract_owner_id).and_return('orcid123')
      allow(described_class).to receive(:extract_owner_org).and_return('ror123')
    end

    it 'returns the :json as-is if :provenance is nil' do
      expect(described_class.annotate_dmp_json(provenance: nil, p_key: p_key, json: dmp)).to eql(dmp)
    end
    it 'returns the :json as-is if :p_key is nil' do
      expect(described_class.annotate_dmp_json(provenance: provenance, p_key: nil, json: dmp)).to eql(dmp)
    end
    it 'returns nil if :json is not parseable' do
      allow(described_class).to receive(:parse_json).and_return(nil)
      expect(described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: 123)).to eql(nil)
    end
    it 'returns the :json as-is if :p_key does not match the :dmp_id' do
      dmp['PK'] = 'DMP#doi.org/99.9999/99999'
      expect(described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)).to eql(dmp)
    end
    it 'returns the expected JSON if :dmphub_provenance_id if not defined in the :json' do
      expected = JSON.parse({
        title: 'Foo bar',
        PK: p_key,
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: 'doi', identifier: "https://#{p_key.gsub(described_class::PK_DMP_PREFIX, '')}" },
        dmproadmap_featured: '0',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: provenance['PK']
      }.to_json)
      result = described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)
      expect(assert_dmps_match(obj_a: result, obj_b: expected, debug: false)).to be(true)
    end
    it 'properly translates :dmproadmap_featured' do
      dmp['dmproadmap_featured'] = 'yes'

      expected = JSON.parse({
        title: 'Foo bar',
        PK: p_key,
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: 'doi', identifier: "https://#{p_key.gsub(described_class::PK_DMP_PREFIX, '')}" },
        dmproadmap_featured: '1',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: provenance['PK']
      }.to_json)
      result = described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)
      expect(assert_dmps_match(obj_a: result, obj_b: expected, debug: false)).to be(true)
    end
    it 'adds the expected JSON if :dmphub_provenance_identifier if not defined in the :json' do
      dmp['dmproadmap_featured'] = 1
      dmp['dmphub_provenance_identifier'] = 'http://foo.bar/dmp/123'
      dmp.delete('dmp_id')

      expected = JSON.parse({
        title: 'Foo bar',
        PK: p_key,
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: "doi", identifier: "https://#{p_key.gsub(described_class::PK_DMP_PREFIX, '')}" },
        dmproadmap_featured: '1',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: provenance['PK'],
        dmphub_provenance_identifier: 'http://foo.bar/dmp/123'
      }.to_json)
      result = described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)
      expect(assert_dmps_match(obj_a: expected, obj_b: result, debug: false)).to be(true)
    end
    it 'retains the DMP ID specified if the provenance is :seedingWithLiveDmpIds' do
      provenance[:seedingWithLiveDmpIds] = true
      dmp['dmp_id'] = 'http://foo.bar/dmp/123'
      dmp['dmproadmap_featured'] = '1'

      expected = JSON.parse({
        title: 'Foo bar',
        PK: "#{described_class::PK_DMP_PREFIX}foo.bar/dmp/123",
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: "doi", identifier: 'http://foo.bar/dmp/123' },
        dmproadmap_featured: '1',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: provenance['PK']
      }.to_json)
      result = described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)
      expect(assert_dmps_match(obj_a: result, obj_b: expected, debug: false)).to be(true)
    end
    it 'does NOT retain the specified DMP ID if the provenance is not :seedingWithLiveDmpIds' do
      dmp['dmp_id'] = JSON.parse({ type: 'url', identifier: 'http://foo.bar/dmp/123' }.to_json)
      dmp['dmproadmap_featured'] = '1'

      expected = JSON.parse({
        title: 'Foo bar',
        PK: p_key,
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: "doi", identifier: "https://#{p_key.gsub(described_class::PK_DMP_PREFIX, '')}" },
        dmproadmap_featured: '1',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: provenance['PK'],
        dmphub_provenance_identifier: 'http://foo.bar/dmp/123'
      }.to_json)
      result = described_class.annotate_dmp_json(provenance: provenance, p_key: p_key, json: dmp)
      expect(assert_dmps_match(obj_a: expected, obj_b: result, debug: false)).to be(true)
    end
  end

  describe 'cleanse_dmp_json(json:)' do
    let!(:dmp) do
      JSON.parse({
        title: 'Foo bar',
        PK: 'FOO',
        SK: described_class::DMP_LATEST_VERSION,
        dmp_id: { type: "doi", identifier: "https://FOO" },
        dmproadmap_featured: '1',
        dmphub_modification_day: Time.now.strftime('%Y-%m-%d'),
        dmphub_owner_id: 'orcid123',
        dmphub_owner_org: 'ror123',
        dmphub_provenance_id: 'fooo',
        dmphub_provenance_identifier: 'http://foo.bar/dmp/123',
        dmphub_foo: 'bar',
        dmphub_modifications: 'still here',
        dmphub_versions: { result: 'still here'}
      }.to_json)
    end

    it 'returns :json as-is if it is not a Hash or Array' do
      expect(described_class.cleanse_dmp_json(json: 123)).to eql(123)
    end
    it 'calls itself for each item if :json is an array' do
      allow(described_class).to receive(:cleanse_dmp_json).twice
      described_class.cleanse_dmp_json(json: [dmp, dmp])
    end
    it 'returns the cleansed :json' do
      expected = JSON.parse({
        title: 'Foo bar',
        dmp_id: { type: "doi", identifier: "https://FOO" },
        dmproadmap_featured: '1',
        dmphub_modifications: 'still here',
        dmphub_versions: { result: 'still here'}
      }.to_json)

      result = described_class.cleanse_dmp_json(json: dmp)
      expect(assert_dmps_match(obj_a: expected, obj_b: result, debug: false)).to be(true)
    end
  end

  describe 'citable_related_identifiers(dmp:)' do
    it 'returns an empty array if :dmp is not a Hash' do
      expect(described_class.citable_related_identifiers(dmp: 123)).to eql([])
    end
    it 'returns the expected :dmproadmap_related_identifiers' do
      dmp = JSON.parse({
        title: 'Foo bar',
        dmp_id: { type: "doi", identifier: "https://FOO" },
        dmproadmap_related_identifiers: [
          { work_type: 'output_management_plan', descriptor: 'is_metadata_for', identifier: 'http://skip.me', type: 'url' },
          { work_type: 'article', descriptor: 'cites', identifier: 'http://skip.me', type: 'doi', citation: 'fooooo' },
          { work_type: 'dataset', descriptor: 'references', identifier: 'http://keep.me', type: 'url', citation: 'baaaarr' },
          { work_type: 'dataset', descriptor: 'references', identifier: 'http://keep.me', type: 'url' },
          { work_type: 'software', descriptor: 'cites', identifier: 'http://keep.me', type: 'url' },
        ]
      }.to_json)
      expected = dmp['dmproadmap_related_identifiers'].reject { |id| id['identifier'] == 'http://skip.me' }
      result = described_class.citable_related_identifiers(dmp: dmp)
      expect(assert_dmps_match(obj_a: expected, obj_b: result, debug: false)).to be(true)
    end
  end

  describe 'deep_copy_dmp(obj:)' do
    it 'makes a copy of the object' do
      obj = JSON.parse({
        foo: {
          array_one: ['a', 'b', 'c'],
          key_one: 'value one',
          nested: {
            array_two: ['Z', 'Y', 'X'],
            key_two: 'value two',
          }
        }
      }.to_json)
      expect(assert_dmps_match(obj_a: described_class.deep_copy_dmp(obj: obj), obj_b: obj, debug: false)).to be(true)
    end
  end
end
