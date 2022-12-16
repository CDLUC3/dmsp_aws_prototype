# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Validator' do
  let!(:described_class) { Validator }

  before do
    dir = "#{Dir.getwd}/layers/ruby/"
    allow(described_class).to receive(:_schema_dir).and_return(dir)
  end

  it 'returns the validation modes' do
    expect(described_class::VALIDATION_MODES.is_a?(Array)).to be(true)
  end

  it 'does not allow the validation modes to be altered' do
    expect { described_class::VALIDATION_MODES << 'foo' }.to raise_error(FrozenError)
  end

  describe 'validate(mode:, json:)' do
    let!(:mode) { 'author' }
    let!(:json) { { foo: 'bar' } }
    let!(:expected_error) { { valid: false, errors: [Messages::MSG_EMPTY_JSON] } }
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
      file = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))
      allow(described_class).to receive(:_load_schema).and_return(file)
    end

    it 'returns the appropriate error when no :mode is specified' do
      result = described_class.validate(mode: nil, json: json)
      expect(compare_hashes(hash_a: result, hash_b: expected_error)).to be(true)
    end

    it 'returns the appropriate error when an invalid :mode is specified' do
      result = described_class.validate(mode: 'foo', json: json)
      expect(compare_hashes(hash_a: result, hash_b: expected_error)).to be(true)
    end

    it 'returns the appropriate error when parse_json returns a nil' do
      allow(described_class).to receive(:parse_json).and_return(nil)
      result = described_class.validate(mode: mode, json: {})
      # expected_error[:errors] = [Messages::MSG_INVALID_JSON]
      expect(compare_hashes(hash_a: result, hash_b: expected_error)).to be(true)
    end

    it 'returns the appropriate error when load_schema returns a nil' do
      allow(described_class).to receive(:_load_schema).and_return(nil)
      expected_error = { valid: false, errors: [Messages::MSG_NO_SCHEMA] }
      result = described_class.validate(mode: mode, json: json)
      expect(compare_hashes(hash_a: result, hash_b: expected_error)).to be(true)
    end

    it 'returns the appropriate error if the :json is NOT valid' do
      json = { bar: 'foo' }
      allow(described_class).to receive(:_load_schema).and_return(schema)
      result = described_class.validate(mode: mode, json: json)
      expect(result[:valid]).to be(false)
      expect(result[:errors].first).to eql(Messages::MSG_INVALID_JSON)
      expect(result[:errors].last.include?('did not contain a required property of \'foo\'')).to be(true)
    end

    it 'returns the appropriate error if the :json is valid' do
      allow(described_class).to receive(:load_schema).and_return(schema)
      json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/minimal.json"))
      result = described_class.validate(mode: mode, json: json['author'])
      expected_error = { valid: true, errors: [] }
      expect(compare_hashes(hash_a: result, hash_b: expected_error)).to be(true)
    end
  end

  describe 'private methods' do
    describe 'parse_json(json:)' do
      it 'returns nil if :json is not provided' do
        expect(described_class.parse_json(json: nil)).to be_nil
      end

      it 'parses the JSON if it is a String' do
        expected = JSON.parse({ foo: 'bar' }.to_json)
        expect(described_class.parse_json(json: '{"foo":"bar"}')).to eql(expected)
      end

      it 'returns nil if :json is not parseable JSON' do
        expect(described_class.parse_json(json: '/{foo:"4%Y"$%\/')).to be_nil
      end

      it 'returns nil if :json is not a Hash or a String' do
        expect(described_class.parse_json(json: 1.34)).to be_nil
      end

      it 'returns the :json as is if it ia a Hash' do
        expected = { foo: 'bar' }
        expect(described_class.parse_json(json: expected)).to eql(expected)
      end
    end

    describe '_load_schema(mode:)' do
      it 'returns nil if :mode is not provided' do
        expect(described_class._load_schema(mode: nil)).to be_nil
      end

      it 'returns nil if :mode is not a valid mode' do
        expect(described_class._load_schema(mode: 'foo')).to be_nil
      end

      it 'returns nil if :mode has no corresponding JSON schema' do
        allow(File).to receive(:exist?).and_return(false)
        expect(described_class._load_schema(mode: :author)).to be_nil
      end

      it 'returns nil if contents of JSON schema are not parseable' do
        allow(File).to receive(:read).and_return('/{foo:"4%Y"$%\/')
        expect(described_class._load_schema(mode: :author)).to be_nil
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
    describe 'config/schemas/minimal.json' do
      let!(:json) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/minimal.json")) }

      it 'minimal author metadata is valid' do
        response = described_class.validate(mode: 'author', json: json['author'])
        expect(response[:valid]).to eql(true), response[:errors].join(', ')
      end

      it 'minimal amend - related_identifiers metadata is valid' do
        response = described_class.validate(mode: 'amend', json: json['amend-related_identifiers'])
        expect(response[:valid]).to eql(true), response[:errors].join(', ')
      end

      it 'minimal amend - funding metadata is valid' do
        response = described_class.validate(mode: 'amend', json: json['amend-funding'])
        expect(response[:valid]).to eql(true), response[:errors].join(', ')
      end
    end

    describe 'config/schemas/complete.json' do
      let!(:json) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }

      # The complete JSON should pass for all modes
      Validator::VALIDATION_MODES.each do |mode|
        it "is valid for mode #{mode}" do
          response = described_class.validate(mode: 'author', json: json)
          expect(response[:valid]).to eql(true), response[:errors].join(', ')
        end
      end
    end
  end

  # Helper function that compares 2 hashes regardless of the order of their keys
  def compare_hashes(hash_a: {}, hash_b: {})
    a_keys = hash_a.keys.sort { |a, b| a <=> b }
    b_keys = hash_b.keys.sort { |a, b| a <=> b }
    return false unless a_keys == b_keys

    valid = true
    a_keys.each { |key| valid = false unless hash_a[key] == hash_b[key] }
    valid
  end
end
