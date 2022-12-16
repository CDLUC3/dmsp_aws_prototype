# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpHelper' do
  let!(:described_class) { DmpHelper }

  let!(:minimal_dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/minimal.json")) }
  let!(:complete_dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }

  describe 'dmps_equal?(dmp_a:, dmp_b:)' do
    let!(:a) do
      a = complete_dmp
      a['PK'] = "#{KeyHelper::PK_DMP_PREFIX}foo"
      a
    end

    it 'returns false if :dmp_a is nil and :dmp_b is not nil' do
      expect(described_class.dmps_equal?(dmp_a: nil, dmp_b: a)).to be(false)
    end

    it 'returns false if :dmp_a is not nil and :dmp_b is nil' do
      expect(described_class.dmps_equal?(dmp_a: a, dmp_b: nil)).to be(false)
    end

    it 'returns false if :dmp_a and :dmp_b :PK do not match' do
      b = described_class.deep_copy_dmp(obj: a)
      b['PK'] = "#{KeyHelper::PK_DMP_PREFIX}#zzzzzzzzzzz"
      expect(described_class.dmps_equal?(dmp_a: a, dmp_b: b)).to be(false)
    end

    it 'ignores expected fields' do
      b = described_class.deep_copy_dmp(obj: a)
      b['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#zzzzzzzzzzz"
      b['dmphub_created_at'] = Time.now.iso8601
      b['dmphub_updated_at'] = Time.now.iso8601
      b['dmphub_modification_day'] = Time.now.strftime('%Y-%M-%d')
      expect(described_class.dmps_equal?(dmp_a: a, dmp_b: b)).to be(true)
    end

    it 'returns false if :dmp_a and :dmp_b do not match' do
      b = described_class.deep_copy_dmp(obj: a)
      b['title'] = 'zzzzzzzzzzz'
      expect(described_class.dmps_equal?(dmp_a: a, dmp_b: b)).to be(false)
    end

    it 'returns true if :dmp_a and :dmp_b match' do
      b = described_class.deep_copy_dmp(obj: a)
      expect(described_class.dmps_equal?(dmp_a: a, dmp_b: b)).to be(true)
    end
  end

  describe 'annotate_dmp(provenance:, p_key:, json:)' do
    let!(:prov) { JSON.parse({ PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" }.to_json) }
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}doi.org/99.88888/7777.66" }
    let!(:json) { minimal_dmp['author'] }

    describe 'for a new DMP' do
      let!(:result) { described_class.annotate_dmp(provenance: prov, json: json, p_key: pk) }

      it 'derives the :PK from the result of :pk_from_dmp_id' do
        expect(result['PK']).to eql(pk)
      end

      it 'sets the :SK to the latest version' do
        expect(result['SK']).to eql(KeyHelper::DMP_LATEST_VERSION)
      end

      it 'sets the :dmphub_provenance_identifier to the :dmp_id' do
        expect(result['dmphub_provenance_identifier']).to eql(json['dmp_id'])
      end

      it 'sets the :dmp_id to the value of the :PK' do
        expected = { type: 'doi', identifier: "https://#{pk.gsub(KeyHelper::PK_DMP_PREFIX, '')}" }
        expect(result['dmp_id']).to eql(expected)
      end

      it 'sets the :dmphub_provenance_id to the current provenance' do
        expect(result['dmphub_provenance_id']).to eql(prov['PK'])
      end

      it 'sets the :dmphub_modification_day to the current date' do
        expect(result['dmphub_modification_day']).to eql(Time.now.strftime('%Y-%m-%d'))
      end

      it 'sets the :dmphub_created_at and :dmphub_updated_at to the current time' do
        expected = Time.now.iso8601
        expect(result['dmphub_created_at']).to be >= expected
        expect(result['dmphub_updated_at']).to be >= expected
      end
    end

    describe 'for an existing DMP' do
      let!(:json) { described_class.annotate_dmp(provenance: prov, json: complete_dmp, p_key: pk) }
      let!(:result) { described_class.annotate_dmp(provenance: prov, json: json, p_key: pk) }

      it 'derives the :PK from the result of :pk_from_dmp_id' do
        expect(result['PK']).to eql(pk)
      end

      it 'sets the :SK to the latest version' do
        expect(result['SK']).to eql(KeyHelper::DMP_LATEST_VERSION)
      end

      it 'does not set the :dmphub_provenance_identifier' do
        expect(result['dmphub_provenance_identifier']).to be_nil
      end

      it 'sets the :dmp_id to the value of the :PK' do
        expected = { type: 'doi', identifier: "https://#{pk.gsub(KeyHelper::PK_DMP_PREFIX, '')}" }
        expect(result['dmp_id']).to eql(expected)
      end

      it 'does not change the :dmphub_provenance_id' do
        expect(result['dmphub_provenance_id']).to eql(json['dmphub_provenance_id'])
      end

      it 'does not change the :dmphub_created_at' do
        expect(result['dmphub_created_at']).to eql(json['dmphub_created_at'])
      end

      it 'sets the :dmphub_modification_day to the current date' do
        expect(result['dmphub_modification_day']).to eql(Time.now.strftime('%Y-%m-%d'))
      end

      it 'sets the :dmphub_created_at and :dmphub_updated_at to the current time' do
        expected = Time.now.iso8601
        expect(result['dmphub_updated_at']).to be >= expected
      end
    end
  end

  # rubocop:disable RSpec/ExampleLength
  describe 'deep_copy_dmp(obj:)' do
    it 'Makes an exact copy including all children' do
      a = {
        PK: "#{KeyHelper::PK_DMP_PREFIX}foo",
        SK: KeyHelper::DMP_LATEST_VERSION,
        dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}bar",
        foo: 'bar',
        items: [
          a: '0',
          b: '2'
        ],
        child: {
          c: '3',
          d: 4,
          e: {
            f: '5',
            g: '6',
            h: %w[foo bar]
          }
        }
      }
      b = described_class.deep_copy_dmp(obj: a)
      expect(a).to eql(b)
      expect(a[:items]).to eql(b[:items])
      expect(a[:child]).to eql(b[:child])
      expect(a[:child][:e]).to eql(b[:child][:e])
      expect(a[:child][:e][:h]).to eql(b[:child][:e][:h])
    end
  end
  # rubocop:enable RSpec/ExampleLength
end
