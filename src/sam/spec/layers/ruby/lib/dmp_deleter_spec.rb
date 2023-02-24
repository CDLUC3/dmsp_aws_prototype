# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpDeleter' do
  let!(:provenance) { JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo" }.to_json) }
  let!(:described_class) do
    DmpDeleter.new(
      provenance: provenance,
      table_name: 'bar',
      client: mock_dynamodb(item_array: []),
      debug_mode: false
    )
  end

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'delete_dmp(p_key:)' do
    let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json")) }
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}foo" }

    before do
      dmp['dmp']['dmphub_provenance_id'] = described_class.provenance['PK']
      dmp['dmp']['SK'] = KeyHelper::DMP_LATEST_VERSION
    end

    it 'returns a 400 error if the :p_key is not present' do
      result = described_class.delete_dmp(p_key: nil)
      expect(result[:status]).to be(400)
      expect(result[:error]).to eql(Messages::MSG_INVALID_ARGS)
    end

    it 'returns a 434 error if the :provenance was not set during initialization' do
      clazz = DmpDeleter.new
      allow(Validator).to receive(:parse_json).and_return(dmp)
      result = clazz.delete_dmp(p_key: pk)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns the error from :find_dmp_by_pk if it does not return a 200' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 500,
                                                                                error: Messages::MSG_SERVER_ERROR })
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end

    it 'returns a 404 if :find_dmp_by_pk did not return a dmp' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [] })
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns a 403 if DMP does not belong to the provenance' do
      dmp['dmp']['dmphub_provenance_id'] = 'bar'
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 405 if it is not the latest version of the DMP' do
      dmp['dmp']['SK'] = "#{KeyHelper::SK_DMP_PREFIX}abcdefg"
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(405)
      expect(result[:error]).to eql(Messages::MSG_DMP_NO_HISTORICALS)
    end

    it 'returns a 200 if the DMP was tombstoned' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      resp = DynamoResponse.new([DynamoItem.new([dmp['dmp']])])
      allow_any_instance_of(DynamoClient).to receive(:update_item).and_return(resp)
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(200)
    end

    it 'returns a 500 if an AWS error is encountered' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(aws_error)
      result = described_class.delete_dmp(p_key: pk)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end
  end

  describe '_post_process(json:)' do
    it 'returns false if :json is not a Hash' do
      expect(described_class._post_process(json: 'foo')).to be(false)
    end

    it 'calls EventPublisher.publish' do
      json = JSON.parse({ PK: 'foo', SK: 'bar' }.to_json)
      dmp = json.clone
      dmp['dmphub_updater_is_provenance'] = true
      expected = { source: 'DmpDeleter', dmp: dmp, debug: false }
      allow(EventPublisher).to receive(:publish).with(expected)
      expect(described_class._post_process(json: json)).to be(true)
    end
  end
end
