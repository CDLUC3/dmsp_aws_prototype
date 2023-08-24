# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Validator' do
  let!(:described_class) { Uc3DmpId::Validator }

  describe 'validate(mode:, json:)' do
    let!(:mode) { 'author' }
    let!(:json) { { foo: 'bar' } }
    let!(:expected_error) { [described_class::MSG_EMPTY_JSON] }
    let!(:schema) do
      {
        type: 'object',
        properties: {
          foo: {
            '$id': '#/properties/foo',
            type: 'string'
          }
        },
        required: [
          'foo'
        ]
      }
    end

    before do
      allow(described_class).to receive(:_load_schema).and_return(mock_dmp(minimal: false))
    end

    it 'returns the appropriate error when no :mode is specified' do
      result = described_class.validate(mode: nil, json: json)
      expect(assert_dmps_match(obj_a: result, obj_b: expected_error, debug: false)).to be(true)
    end

    it 'returns the appropriate error when an invalid :mode is specified' do
      result = described_class.validate(mode: 'foo', json: json)
      expect(assert_dmps_match(obj_a: result, obj_b: expected_error, debug: false)).to be(true)
    end

    it 'returns the appropriate error when parse_json returns a nil' do
      allow(Uc3DmpId::Helper).to receive(:parse_json).and_return(nil)
      result = described_class.validate(mode: mode, json: {})
      expect(assert_dmps_match(obj_a: result, obj_b: expected_error, debug: false)).to be(true)
    end

    it 'returns the appropriate error when load_schema returns a nil' do
      allow(described_class).to receive(:_load_schema).and_return(nil)
      expected_error = [described_class::MSG_NO_SCHEMA]
      result = described_class.validate(mode: mode, json: json)
      expect(assert_dmps_match(obj_a: result, obj_b: expected_error, debug: false)).to be(true)
    end

    it 'returns the appropriate error if the :json is NOT valid' do
      json = { bar: 'foo' }
      allow(described_class).to receive(:_load_schema).and_return(schema)
      result = described_class.validate(mode: mode, json: json)
      expect(result.last.include?('did not contain a required property of \'foo\'')).to be(true)
    end

    it 'returns the appropriate error if the :json is valid' do
      allow(described_class).to receive(:load_schema).and_return(schema)
      json = { foo: 'bar' }
      result = described_class.validate(mode: mode, json: json)
      expected_error = []
      expect(assert_dmps_match(obj_a: result, obj_b: expected_error, debug: false)).to be(true)
    end
  end

  describe 'private methods' do
    describe '_load_schema(mode:)' do
      it 'returns nil if :mode is not provided' do
        expect(described_class._load_schema(mode: nil)).to be_nil
      end

      it 'returns nil if :mode is not a valid mode' do
        expect(described_class._load_schema(mode: 'foo')).to be_nil
      end

      it 'returns the JSON schema' do
        schema = described_class._load_schema(mode: :author)
        expected = 'https://github.com/CDLUC3/dmp-hub-sam/layer/ruby/config/schemas/author.json'
        expect(schema['$id']).to eql(expected)

        schema = described_class._load_schema(mode: :amend)
        expected = 'https://github.com/CDLUC3/dmp-hub-sam/layer/ruby/config/schemas/amend.json'
        expect(schema['$id']).to eql(expected)
      end
    end
  end

  describe 'Ensure our JSON Schemas are working as expected' do
    # The following tests are used to validate the JSON schema documents to ensure
    # that a minimal metadata record and a complete metadata record are valid
    describe 'spec/support/json_mocks/minimal.json' do
      let!(:json) { mock_dmp(minimal: true) }

      it 'minimal author metadata is valid' do
        expect(described_class.validate(mode: 'author', json: json['author'])).to eql([])
      end

      it 'minimal amend - related_identifiers metadata is valid' do
        expect(described_class.validate(mode: 'amend', json: json['amend-related_identifiers'])).to eql([])
      end

      it 'minimal amend - funding metadata is valid' do
        expect(described_class.validate(mode: 'amend', json: json['amend-funding'])).to eql([])
      end
    end

    describe 'spec/support/json_mocks/complete.json' do
      let!(:json) { mock_dmp(minimal: false) }

      # The complete JSON should pass for all modes
      Uc3DmpId::Validator::VALIDATION_MODES.each do |mode|
        it "is valid for mode #{mode}" do
          expect(described_class.validate(mode: 'author', json: json)).to eql([])
        end
      end
    end
  end
end
