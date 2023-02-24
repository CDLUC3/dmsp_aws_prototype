# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpUpdater' do
  let!(:provenance) { JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo" }.to_json) }
  let!(:described_class) do
    DmpUpdater.new(
      provenance: provenance,
      table_name: 'bar',
      client: mock_dynamodb(item_array: []),
      debug_mode: false
    )
  end
  let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'update_dmp(lambda_context:, p_key:, json: {}, **args)' do
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}foo" }

    before do
      dmp['dmp']['PK'] = pk
      dmp['dmp']['SK'] = KeyHelper::DMP_LATEST_VERSION
      dmp['dmp']['dmphub_provenance_id'] = provenance['PK']
    end

    it 'returns a 400 error if the :json is not parseable' do
      result = described_class.update_dmp(json: 3.3, p_key: pk)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 400 error if the :p_key was not specified' do
      result = described_class.update_dmp(json: dmp, p_key: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 403 error if the :provenance was not set during initialization' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      result = described_class.update_dmp(json: dmp, p_key: pk)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 403 :p_key does not match the :json' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return("#{KeyHelper::PK_DMP_PREFIX}bar")
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 405 if it is not the latest version of the DMP' do
      dmp['dmp']['SK'] = "#{KeyHelper::SK_DMP_PREFIX}abcdefg"
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(405)
      expect(result[:error]).to eql(Messages::MSG_DMP_NO_HISTORICALS)
    end

    it 'returns a 404 if the DmpVersioner returns a nil' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      allow_any_instance_of(DmpVersioner).to receive(:new_version).and_return(nil)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_UNABLE_TO_VERSION)
    end

    it 'handles AWS DuplicateItemException' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      allow_any_instance_of(DmpVersioner).to receive(:new_version).and_return(dmp)
      error = Aws::DynamoDB::Errors::DuplicateItemException.new(
        Seahorse::Client::RequestContext.new, 'Duplicate!'
      )
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(error)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(405)
      expect(result[:error]).to eql(Messages::MSG_DMP_EXISTS)
    end

    it 'handles AWS ServiceError' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow(DmpHelper).to receive(:annotate_dmp).and_return(dmp)
      allow_any_instance_of(DmpVersioner).to receive(:new_version).and_return(dmp)
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(aws_error)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end
  end

  describe '_post_process(json:)' do
    it 'returns false if :json is not a Hash' do
      expect(described_class._post_process(json: 'foo')).to be(false)
    end

    it 'calls EventPublisher.publish when updater is the system of prvoenance' do
      json = JSON.parse({ PK: 'foo', SK: 'bar' }.to_json)
      json['dmphub_provenance_id'] = provenance['PK']
      dmp = json.clone
      dmp['dmphub_updater_is_provenance'] = true
      expected = { source: 'DmpUpdater', dmp: dmp, debug: false }
      allow(EventPublisher).to receive(:publish).with(expected)
      expect(described_class._post_process(json: json)).to be(true)
    end

    it 'calls EventPublisher.publish when updater is NOT the system of prvoenance' do
      json = JSON.parse({ PK: 'foo', SK: 'bar' }.to_json)
      json['dmphub_provenance_id'] = 'baz'
      dmp = json.clone
      dmp['dmphub_updater_is_provenance'] = false
      expected = { source: 'DmpUpdater', dmp: dmp, debug: false }
      allow(EventPublisher).to receive(:publish).with(expected)
      expect(described_class._post_process(json: json)).to be(true)
    end
  end
end
