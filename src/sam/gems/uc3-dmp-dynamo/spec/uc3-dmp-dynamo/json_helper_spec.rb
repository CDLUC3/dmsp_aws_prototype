# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpDynamo::JsonHelper' do
  let!(:described_class) { Uc3DmpDynamo::JsonHelper }

  let!(:url) { 'https://api.example.com/dmps/' }

  describe 'cleanse_dmp_json(json:)' do
    it 'returns the :json as is if it is not a Hash or an Array' do
      json = 'foo'
      expect(described_class.cleanse_dmp_json(json: json)).to eql(json)
    end

    it 'calls itdescribed_class recursively for each item if it is an Array' do
      json = [
        { dmphub_a: 'foo' },
        { foo: 'bar' }
      ]
      expect(described_class.cleanse_dmp_json(json: json)).to eql([{ foo: 'bar' }])
    end

    it 'removes all entries that start with "dmphub"' do
      json = [
        { dmphub_a: 'foo' },
        { dmphubb: 'bar' }
      ]
      expect(described_class.cleanse_dmp_json(json: json)).to eql([])
    end

    it 'removes the PK and SK entries' do
      json = [
        { PK: 'DMP#foo' },
        { SK: 'VERSION#bar' }
      ]
      expect(described_class.cleanse_dmp_json(json: json)).to eql([])
    end

    # rubocop:disable RSpec/ExampleLength
    it 'recursively cleanses child Hashes and Arrays' do
      json = {
        'child-1': {
          dmphub_a: 'foo',
          foo: 'bar'
        },
        'child-2': [
          { dmphub_b: 'bar' },
          { bar: 'foo' }
        ],
        dmphub_c: {
          baz: 'hey'
        }
      }
      expected = { 'child-1': { foo: 'bar' }, 'child-2': [{ bar: 'foo' }] }
      result = described_class.cleanse_dmp_json(json: json)
      expect(result).to eql(expected)
    end
  end
  # rubocop:enable RSpec/ExampleLength
end