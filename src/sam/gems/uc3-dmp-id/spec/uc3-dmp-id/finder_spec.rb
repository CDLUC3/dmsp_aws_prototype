# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Finder' do
  let!(:described_class) { Uc3DmpId::Finder }
  let!(:finder_error) { Uc3DmpId::FinderError }

  let!(:dmp) do
    record = mock_dmp
    record['dmp']['PK'] = "#{Uc3DmpId::Helper::PK_DMP_PREFIX}test"
    record
  end
  let!(:client) { mock_uc3_dmp_dynamo(dmp:) }

  describe 'search_dmps(args:, logger: nil)' do
    it 'returns an empty Array if :args does not contain any valid query criteria' do
      expect(described_class.search_dmps(args: JSON.parse({ foo: 'bar' }.to_json))).to eql([])
    end

    it 'calls :_by_owner if :args includes an :owner_orcid' do
      allow(described_class).to receive(:_by_owner).once
      expect(described_class.search_dmps(args: JSON.parse({ foo: 'bar' }.to_json))).to eql([])
    end

    it 'calls :_by_owner_org if :args includes an :owner_org_ror' do
      allow(described_class).to receive(:_by_owner_org).once
      expect(described_class.search_dmps(args: JSON.parse({ foo: 'bar' }.to_json))).to eql([])
    end

    it 'calls :_by_mod_day if :args includes an :modification_day' do
      allow(described_class).to receive(:_by_mod_day).once
      expect(described_class.search_dmps(args: JSON.parse({ foo: 'bar' }.to_json))).to eql([])
    end
  end

  describe 'by_json(json:, cleanse: true, logger: nil)' do
    let!(:json) do
      JSON.parse({
        dmp: {
          dmp_id: { type: 'doi', identifier: 'http://doi.org/11.4444/HH33JJ' },
          title: 'Testing find by JSON'
        }
      }.to_json)
    end

    it 'raises a FinderError if :json is not a Hash' do
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(nil)
      expect { described_class.by_json(json: '123', client:) }.to raise_error(finder_error)
    end

    it 'raises a FinderError if :json does not contain a :PK or :dmp_id' do
      json['dmp'].delete('dmp_id')
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(json)
      expect { described_class.by_json(json: '123', client:) }.to raise_error(finder_error)
    end

    it 'calls :by_pk if the :json contains a :dmp_id' do
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(json)
      allow(described_class).to receive(:by_pk).and_return(json)
      described_class.by_json(json:, client:)
      expect(described_class).to have_received(:by_pk).once
    end

    it 'calls :by_pk if the :json contains a :PK' do
      json['dmp']['PK'] = json['dmp']['dmp_id']['identifier']
      json['dmp'].delete('dmp_id')
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(json)
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(json)
      allow(described_class).to receive(:by_pk).and_return(json)
      described_class.by_json(json:, client:)
      expect(described_class).to have_received(:by_pk).once
    end
  end

  describe 'by_pk(p_key:, s_key: Helper::DMP_LATEST_VERSION, client: nil, cleanse: true, logger: nil)' do
    it 'raises a FinderError if :p_key is nil' do
      expect { described_class.by_pk(p_key: nil, client:) }.to raise_error(finder_error)
    end

    it 'uses the default SK if no :s_key is specified' do
      allow(Uc3DmpId::Versioner).to receive(:append_versions).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:cleanse_dmp_json).and_return(dmp)
      expect(described_class.by_pk(p_key: 'foo', client:).length).to be(1)
      expect(Uc3DmpId::Versioner).to have_received(:append_versions).once
      expected = {
        key: { PK: "#{Uc3DmpId::Helper::PK_DMP_PREFIX}foo", SK: Uc3DmpId::Helper::DMP_LATEST_VERSION },
        logger: nil
      }
      expect(client).to have_received(:get_item).with(expected)
    end

    it 'calls Dynamo with the expected query args' do
      allow(Uc3DmpId::Versioner).to receive(:append_versions).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:cleanse_dmp_json).and_return(dmp)
      expect(described_class.by_pk(p_key: 'foo', s_key: 'bar', client:).length).to be(1)
      expect(Uc3DmpId::Versioner).to have_received(:append_versions).once
      expected = {
        key: { PK: "#{Uc3DmpId::Helper::PK_DMP_PREFIX}foo", SK: "#{Uc3DmpId::Helper::SK_DMP_PREFIX}bar" },
        logger: nil
      }
      expect(client).to have_received(:get_item).with(expected)
    end

    it 'appends the :dmphub_versions' do
      allow(Uc3DmpId::Versioner).to receive(:append_versions).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:cleanse_dmp_json).and_return(dmp)
      described_class.by_pk(p_key: 'foo', s_key: 'bar', client:)
      expect(Uc3DmpId::Versioner).to have_received(:append_versions).once
    end

    it 'cleanses the :dmphub_ prefixed attributes by default' do
      allow(Uc3DmpId::Versioner).to receive(:append_versions).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:cleanse_dmp_json).and_return(dmp)
      described_class.by_pk(p_key: 'foo', s_key: 'bar', client:)
      expect(Uc3DmpId::Helper).to have_received(:cleanse_dmp_json).once
    end

    it 'does not cleanse the :dmphub_ prefixed attributes if specified' do
      allow(Uc3DmpId::Versioner).to receive(:append_versions).and_return(dmp)
      allow(Uc3DmpId::Helper).to receive(:cleanse_dmp_json).and_return(dmp)
      described_class.by_pk(p_key: 'foo', s_key: 'bar', client:, cleanse: false)
      expect(Uc3DmpId::Helper).not_to have_received(:cleanse_dmp_json)
    end
  end

  describe 'exists?(p_key:, s_key: Helper::DMP_LATEST_VERSION, client: nil, logger: nil)' do
    it 'raises a FinderError if :p_key is nil' do
      expect { described_class.exists?(p_key: nil, client:) }.to raise_error(finder_error)
    end

    it 'uses the default SK if no :s_key is specified' do
      expect(described_class.exists?(p_key: 'foo', client:)).to be(true)
      expected = {
        key: { PK: "#{Uc3DmpId::Helper::PK_DMP_PREFIX}foo", SK: Uc3DmpId::Helper::DMP_LATEST_VERSION },
        logger: nil
      }
      expect(client).to have_received(:pk_exists?).with(expected)
    end

    it 'calls Dynamo with the expected query args' do
      expect(described_class.exists?(p_key: 'foo', s_key: 'bar', client:)).to be(true)
      expected = {
        key: { PK: "#{Uc3DmpId::Helper::PK_DMP_PREFIX}foo", SK: "#{Uc3DmpId::Helper::SK_DMP_PREFIX}bar" },
        logger: nil
      }
      expect(client).to have_received(:pk_exists?).with(expected)
    end
  end

  describe 'by_provenance_identifier(json:, client: nil, cleanse: true, logger: nil)' do
    let!(:json) do
      JSON.parse({
        title: 'Testing',
        dmp_id: { type: 'url', identifier: 'http://some.org/12345' }
      }.to_json)
    end

    it 'raises a FinderError if :json is not a Hash' do
      expect { described_class.by_provenance_identifier(json: nil, client:) }.to raise_error(finder_error)
    end

    it 'raises a FinderError if :json does not contain a :dmp_id with a :identifier' do
      expect { described_class.by_provenance_identifier(json: {}, client:) }.to raise_error(finder_error)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'can handle it when :json has a top level :dmp' do
      nested = JSON.parse({ dmp: json }.to_json)
      expect(described_class.by_provenance_identifier(json: nested, client:).length).to be(1)
      expected = {
        args: {
          expression_attribute_values: { ':version': Uc3DmpId::Helper::DMP_LATEST_VERSION },
          filter_expression: 'SK = :version',
          index_name: 'dmphub_provenance_identifier_gsi',
          key_conditions: {
            dmphub_provenance_identifier: {
              attribute_value_list: ['http://some.org/12345'],
              comparison_operator: 'EQ'
            }
          }
        },
        logger: nil
      }
      expect(client).to have_received(:query).with(expected)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'calls Dynamo with the expected query args' do
      expect(described_class.by_provenance_identifier(json:, client:).length).to be(1)
      expected = {
        args: {
          expression_attribute_values: { ':version': Uc3DmpId::Helper::DMP_LATEST_VERSION },
          filter_expression: 'SK = :version',
          index_name: 'dmphub_provenance_identifier_gsi',
          key_conditions: {
            dmphub_provenance_identifier: {
              attribute_value_list: ['http://some.org/12345'],
              comparison_operator: 'EQ'
            }
          }
        },
        logger: nil
      }
      expect(client).to have_received(:query).with(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_by_owner(owner_id:, logger: nil)' do
    it 'raises a FinderError if :_by_owner is nil' do
      expect { described_class.send(:_by_owner, owner_id: nil) }.to raise_error(finder_error)
    end

    it 'raises a FinderError if :owner_org is not an ORCID id' do
      expect { described_class.send(:_by_owner, owner_id: '12345') }.to raise_error(finder_error)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'calls Dynamo with the expected query args' do
      expect(described_class.send(:_by_owner, owner_id: '0000-0000-0000-TEST', client:).length).to be(1)
      expected = {
        args: {
          expression_attribute_values: { ':version': Uc3DmpId::Helper::DMP_LATEST_VERSION },
          filter_expression: 'SK = :version',
          index_name: 'dmphub_owner_id_gsi',
          key_conditions: {
            dmphub_owner_id: {
              attribute_value_list: ['http://orcid.org/0000-0000-0000-TEST', 'https://orcid.org/0000-0000-0000-TEST'],
              comparison_operator: 'IN'
            }
          }
        },
        logger: nil
      }
      expect(client).to have_received(:query).with(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_by_owner_org(owner_org:, logger: nil)' do
    it 'raises a FinderError if :owner_org is nil' do
      expect { described_class.send(:_by_owner_org, owner_org: nil) }.to raise_error(finder_error)
    end

    it 'raises a FinderError if :owner_org is not a ROR id' do
      expect { described_class.send(:_by_owner_org, owner_org: '536.45t245/wefwRT') }.to raise_error(finder_error)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'calls Dynamo with the expected query args' do
      expect(described_class.send(:_by_owner_org, owner_org: '123abc45', client:).length).to be(1)
      expected = {
        args: {
          expression_attribute_values: { ':version': Uc3DmpId::Helper::DMP_LATEST_VERSION },
          filter_expression: 'SK = :version',
          index_name: 'dmphub_owner_org_gsi',
          key_conditions: {
            dmphub_owner_org: {
              attribute_value_list: ['https://ror.org/123abc45', 'http://ror.org/123abc45'],
              comparison_operator: 'IN'
            }
          }
        },
        logger: nil
      }
      expect(client).to have_received(:query).with(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_by_mod_day(day:, logger: nil)' do
    it 'raises a FinderError if :day is nil' do
      expect { described_class.send(:_by_mod_day, day: nil) }.to raise_error(finder_error)
    end

    it 'raises a FinderError if :day does not match the YYYY-MM-DD format' do
      expect { described_class.send(:_by_mod_day, day: '10/23/2020') }.to raise_error(finder_error)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'calls Dynamo with the expected query args' do
      expect(described_class.send(:_by_mod_day, day: '2023-08-21', client:).length).to be(1)
      expected = {
        args: {
          expression_attribute_values: { ':version': Uc3DmpId::Helper::DMP_LATEST_VERSION },
          filter_expression: 'SK = :version',
          index_name: 'dmphub_modification_day_gsi',
          key_conditions: {
            dmphub_modification_day: { attribute_value_list: ['2023-08-21'], comparison_operator: 'IN' }
          }
        },
        logger: nil
      }
      expect(client).to have_received(:query).with(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_process_search_response(response:)' do
    it 'returns an empty Array unless :response is an Array' do
      expect(described_class.send(:_process_search_response, response: { foo: 'bar' })).to eql([])
    end

    it 'adds a top level :dmp to each item' do
      items = JSON.parse([{ title: 'Test one' }, { title: 'Test two' }].to_json)
      result = described_class.send(:_process_search_response, response: items)
      expect(result.length).to be(2)
      expect(result.first).to eql(JSON.parse({ dmp: items.first }.to_json))
      expect(result.last).to eql(JSON.parse({ dmp: items.last }.to_json))
    end

    # rubocop:disable RSpec/ExampleLength
    it 'calls Helper.cleanse_dmp_json for each item' do
      items = JSON.parse([{
        PK: 'foo',
        SK: 'bar',
        title: 'Test one',
        dmphub_provenance_id: 'baz',
        dmphub_modification_day: '2020-01-02',
        dmphub_owner_id: 'orcid',
        dmphub_owner_org: 'ror',
        dmphub_provenance_identifier: '12345',
        dmphub_test: 'should go away',
        dmphub_versions: %w[one two],
        dmphub_modifications: %w[three four]
      }].to_json)
      result = described_class.send(:_process_search_response, response: items)
      expect(result.length).to be(1)

      expected = JSON.parse({
        dmp: {
          title: 'Test one',
          dmphub_versions: %w[one two],
          dmphub_modifications: %w[three four]
        }
      }.to_json)
      expect(assert_dmps_match(obj_a: result.first, obj_b: expected, debug: false)).to be(true)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'removes nils and dupicates' do
      items = JSON.parse([{ title: 'Test one' }, { title: 'Test two' }, nil, { title: 'Test one' }].to_json)
      result = described_class.send(:_process_search_response, response: items)
      expect(result.length).to be(2)
      expect(result.first).to eql(JSON.parse({ dmp: items.first }.to_json))
      expect(result.last).to eql(JSON.parse({ dmp: items[1] }.to_json))
    end
  end

  describe '_remove_narrative_if_private(json:)' do
    let!(:json) do
      JSON.parse({
        dmp: {
          dmproadmap_privacy: 'private',
          dmproadmap_related_identifiers: [
            { descriptor: 'references', work_type: 'dataset', type: 'doi', identifier: 'dataset' },
            { descriptor: 'references', work_type: 'output_management_plan', type: 'doi', identifier: 'other_dmp' },
            { descriptor: 'is_metadata_for', work_type: 'dataset', type: 'doi', identifier: 'fake_narrative' },
            { descriptor: 'is_metadata_for', work_type: 'output_management_plan', type: 'doi', identifier: 'narrative' }
          ]
        }
      }.to_json)
    end

    it 'returns the :json as-is if the DMP is "public"' do
      json['dmp']['dmproadmap_privacy'] = 'public'
      expect(described_class.send(:_remove_narrative_if_private, json:)).to eql(json)
    end

    it 'returns the :json as-is if the DMP has no narrative' do
      json['dmp']['dmproadmap_related_identifiers'] = json['dmp']['dmproadmap_related_identifiers'].reject do |id|
        id['descriptor'] == 'is_metadata_for' && id['work_type'] == 'output_management_plan'
      end
      expect(described_class.send(:_remove_narrative_if_private, json:)).to eql(json)
    end

    it 'returns the :json without the narrative' do
      resp = described_class.send(:_remove_narrative_if_private, json:)
      ids = resp['dmp']['dmproadmap_related_identifiers'].map { |id| id['identifier'] }
      expect(ids.length).to be(3)
      expect(ids.include?('dataset')).to be(true)
      expect(ids.include?('other_dmp')).to be(true)
      expect(ids.include?('fake_narrative')).to be(true)
      expect(ids.include?('narrative')).to be(false)
    end
  end
end
