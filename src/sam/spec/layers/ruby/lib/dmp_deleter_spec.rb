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
  let!(:sns_client) { mock_sns(success: true) }

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
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

  describe '_post_process(p_key:)' do
    let!(:publish_subject) { 'DmpDeleter - tombstone DMP ID - BAR' }
    let!(:publish_message) { { action: 'tombstone', provenance: provenance['PK'], dmp: 'BAR' }.to_json }

    it 'returns false if :p_key is nil' do
      expect(described_class._post_process(p_key: nil)).to be(false)
    end

    it 'returns false if :p_key is an empty string' do
      expect(described_class._post_process(p_key: '')).to be(false)
    end

    it 'attempts to publish a message to the SNS_PUBLISH_TOPIC' do
      expect(described_class._post_process(p_key: 'BAR')).to be(true)
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: publish_subject,
                                                         message: publish_message).once
    end
  end
end
