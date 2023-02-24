# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpCreator' do
  let!(:provenance) { JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo" }.to_json) }
  let!(:described_class) do
    DmpCreator.new(
      provenance: provenance,
      table_name: 'bar',
      client: mock_dynamodb(item_array: []),
      debug_mode: false
    )
  end
  let!(:sns_client) { mock_sns(success: true) }
  let!(:finder) { DmpFinder.new(table: 'foo', client: nil, provenance: provenance) }

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'create_dmp(json: {}, **args)' do
    let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}foo" }

    it 'returns a 400 error if the :json is not parseable' do
      result = described_class.create_dmp(json: 3.3)
      expect(result[:status]).to be(400)
      expect(result[:error]).to eql(Messages::MSG_INVALID_ARGS)
    end

    it 'returns a 403 error if the :provenance was not set during initialization' do
      clazz = DmpCreator.new
      allow(clazz).to receive(:parse_json).and_return(dmp)
      allow(clazz).to receive(:provenance).and_return(nil)
      result = clazz.create_dmp(json: dmp)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 500 error if :find_dmp_by_json returns a 500 error' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      expected = { status: 500, error: Messages::MSG_SERVER_ERROR }
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return(expected)
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end

    it 'returns a 400 error if the DMP already exists' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return({ status: 200, items: [dmp] })
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(400)
      expect(result[:error]).to eql(Messages::MSG_DMP_EXISTS)
    end

    it 'returns a 500 if we could not register a DMP ID' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return({ status: 404, items: [] })
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(nil)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(nil)
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_DMP_NO_DMP_ID)
    end

    it 'returns a non-201 if we could not create the DMP' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return({ status: 404, items: [] })
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(nil)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      expected = { status: 403, error: Messages::MSG_DMP_FORBIDDEN }
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return(expected)
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 201 if the DMP was created' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return({ status: 404, items: [] })
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(nil)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      resp = DynamoResponse.new([DynamoItem.new(dmp)])
      allow_any_instance_of(DynamoClient).to receive(:update_item).and_return(resp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(201)
      expect(result[:items].first).to eql(dmp)
    end

    it 'returns a 500 if and AWS error occurs during create_dmp_dmp' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_json).and_return({ status: 404, items: [] })
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(nil)
      allow(described_class).to receive(:_preregister_dmp_id).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(aws_error)
      result = described_class.create_dmp(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end
  end

  describe '_preregister_dmp_id' do
    # SsmReader activity returns 'foo' for tests, so the DMP_ID_BASE_URL and DMP_ID_SHOULDER
    # will be 'foo'
    let!(:expected) { "#{KeyHelper::PK_DMP_PREFIX}foo/foo" }

    describe 'when :provenance can retain their specified :dmp_id' do
      let!(:described_class) do
        DmpCreator.new(
          provenance: JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo", seedingWithLiveDmpIds: true }.to_json),
          table_name: 'bar',
          client: mock_dynamodb(item_array: []),
          debug_mode: false
        )
      end

      it 'allows :provenance to :retain their specified :dmp_id if they have permission' do
        id = { dmp_id: { type: 'doi', identifier: 'foo' } }
        allow(described_class).to receive(:_dmp_id_exists?).and_return(false)
        result = described_class._preregister_dmp_id(finder: finder, json: JSON.parse(id.to_json))
        expect(result).to eql(id[:dmp_id][:identifier])
      end

      it 'does NOT allow :provenance to :retain their specified :dmp_id if the DMP ID exists' do
        id = { dmp_id: { type: 'doi', identifier: 'foo' } }
        allow(described_class).to receive(:_dmp_id_exists?).and_return(true)
        result = described_class._preregister_dmp_id(finder: finder, json: JSON.parse(id.to_json))
        expect(result).not_to eql(id[:dmp_id][:identifier])
      end
    end

    it 'returns a new unique DMP ID' do
      allow(described_class).to receive(:can_skip_preregister).and_return(false)
      allow(described_class).to receive(:_dmp_id_exists?).and_return(false)
      first = described_class._preregister_dmp_id(finder: finder, json: {})
      second = described_class._preregister_dmp_id(finder: finder, json: {})
      expect(first.start_with?(expected)).to be(true)
      expect(second.start_with?(expected)).to be(true)
      expect(first.gsub(expected, '')).not_to eql(second.gsub(expected, ''))
    end

    it 'has the expected length and format' do
      allow(described_class).to receive(:can_skip_preregister).and_return(false)
      allow(described_class).to receive(:_dmp_id_exists?).and_return(false)
      regex = /[A-Z0-9]{4}[a-z0-9]{4}/
      result = described_class._preregister_dmp_id(finder: finder, json: {})
      expect(result.length).to eql(expected.length + 8)
      expect(result =~ regex).not_to eql(nil)
    end

    it 'returns a nil if a unique id could not determined after 10 attempts' do
      allow(described_class).to receive(:can_skip_preregister).and_return(false)
      allow(described_class).to receive(:_dmp_id_exists?).and_return(true).at_least(10).times
      expect(described_class._preregister_dmp_id(finder: finder, json: {})).to be_nil
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '_post_process(provenance:, p_key:, json:)' do
    let!(:json) do
      JSON.parse({
        dmproadmap_related_identifiers: [
          { work_type: 'output_management_plan', descriptor: 'is_metadata_for', identifier: 'url' }
        ]
      }.to_json)
    end
    let!(:publish_subject) { 'DmpCreator - register DMP ID - BAR' }
    let!(:publish_message) { { action: 'create', provenance: provenance['PK'], dmp: 'BAR' }.to_json }
    let!(:download_subject) { 'DmpCreator - fetch DMP document - BAR' }
    let!(:download_message) { { provenance: provenance['PK'], dmp: 'BAR', location: 'url' }.to_json }

    it 'returns false if :p_key is nil' do
      expect(described_class._post_process(provenance: provenance, p_key: nil, json: json)).to be(false)
    end

    xit 'skips EZID publication if :provenance is :seedingWithLiveDmpIds' do
      # TODO: Implement this test
    end

    it 'returns false if :p_key is an empty string' do
      expect(described_class._post_process(provenance: provenance, p_key: '', json: json)).to be(false)
    end

    it 'attempts to publish a message to the SNS_PUBLISH_TOPIC' do
      json['dmproadmap_related_identifiers'].first['descriptor'] = 'version_of'
      expect(described_class._post_process(provenance: provenance, p_key: 'BAR', json: json)).to be(true)
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: publish_subject,
                                                         message: publish_message).once
      expect(sns_client).not_to have_received(:publish).with(topic_arn: 'foo', subject: download_subject,
                                                             message: download_message)
    end

    it 'attempts to publish a message to the SNS_DOWNLOAD_TOPIC' do
      expect(described_class._post_process(provenance: provenance, p_key: 'BAR', json: json)).to be(true)
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: publish_subject,
                                                         message: publish_message).once
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: download_subject,
                                                         message: download_message).once
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe 'dmp_id_exists?(finder:, hash:)' do
    it 'returns false if the :dmp_id is not a Hash' do
      expect(described_class._dmp_id_exists?(finder: finder, hash: 123)).to be(false)
    end

    it 'returns false if the :dmp_id is not a DOI' do
      json = JSON.parse({ type: 'url', identifier: 'http://example.com/foo' }.to_json)
      expect(described_class._dmp_id_exists?(finder: finder, hash: json)).to be(false)
    end

    it 'returns false if the :dmp_id does not contain an :identifier' do
      json = JSON.parse({ type: 'doi' }.to_json)
      expect(described_class._dmp_id_exists?(finder: finder, hash: json)).to be(false)
    end

    it 'returns true if the DmpFinder returns a 200' do
      allow(finder).to receive(:find_dmp_by_pk).and_return({ status: 200 })
      json = JSON.parse({ type: 'doi', identifier: 'http://example.com/foo' }.to_json)
      expect(described_class._dmp_id_exists?(finder: finder, hash: json)).to be(true)
    end

    it 'returns true if the DmpFinder returns a 404' do
      allow(finder).to receive(:find_dmp_by_pk).and_return({ status: 404 })
      json = JSON.parse({ type: 'doi', identifier: 'http://example.com/foo' }.to_json)
      expect(described_class._dmp_id_exists?(finder: finder, hash: json)).to be(false)
    end
  end
end
