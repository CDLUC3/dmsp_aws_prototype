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
  let!(:sns_client) { mock_sns(success: true) }

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
      dmp['dmp']['dmphub_provenance_id'] = "#{KeyHelper::PK_DMP_PREFIX}foo"
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

    it 'returns the result from :find_dmp_by_pk if it did not return a 200' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      expected = { status: 501, error: 'testing foo' }
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return(expected)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(501)
      expect(result[:error]).to eql(expected[:error])
    end

    it 'returns a 404 if the :p_key had no record in the DB' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [] })
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns a 403 if DMP does not belong to the provenance' do
      dmp['dmp']['dmphub_provenance_id'] = 'bar'
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns a 405 if it is not the latest version of the DMP' do
      dmp['dmp']['SK'] = "#{KeyHelper::SK_DMP_PREFIX}abcdefg"
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(405)
      expect(result[:error]).to eql(Messages::MSG_DMP_NO_HISTORICALS)
    end

    it 'returns the result from :_version_it if it did not return a 200' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      expected = { status: 501, error: 'testing foo' }
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      allow(described_class).to receive(:_version_it).and_return(expected)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(501)
      expect(result[:error]).to eql(expected[:error])
    end

    it 'calls :annotate_dmp and :_process_update and returns 200 if successful' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      allow(described_class).to receive(:_version_it).and_return({ status: 200, items: [dmp['dmp']] })
      allow(DmpHelper).to receive(:annotate_dmp)
      allow(described_class).to receive(:_process_update)
      resp = DynamoResponse.new([DynamoItem.new([dmp['dmp']])])
      allow_any_instance_of(DynamoClient).to receive(:update_item).and_return(resp)
      described_class.update_dmp(p_key: pk, json: dmp)
      expect(described_class).to have_received(:_process_update).once
    end

    # rubocop:disable RSpec/ExampleLength
    it 'handles AWS DuplicateItemException' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      allow(described_class).to receive(:_version_it).and_return({ status: 200, items: [dmp['dmp']] })
      allow(DmpHelper).to receive(:annotate_dmp)
      allow(described_class).to receive(:_process_update).and_return(dmp)
      error = Aws::DynamoDB::Errors::DuplicateItemException.new(
        Seahorse::Client::RequestContext.new, 'Duplicate!'
      )
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(error)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(405)
      expect(result[:error]).to eql(Messages::MSG_DMP_EXISTS)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'handles AWS ServiceError' do
      allow(Validator).to receive(:parse_json).and_return(dmp)
      allow(KeyHelper).to receive(:dmp_id_to_pk).and_return(pk)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      allow(described_class).to receive(:_version_it).and_return({ status: 200, items: [dmp['dmp']] })
      allow(DmpHelper).to receive(:annotate_dmp)
      allow(described_class).to receive(:_process_update).and_return(dmp)
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(aws_error)
      result = described_class.update_dmp(p_key: pk, json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '_post_process(p_key:, json:)' do
    let!(:json) do
      JSON.parse({
        dmproadmap_related_identifiers: [
          { work_type: 'output_management_plan', descriptor: 'is_metadata_for', identifier: 'url' }
        ]
      }.to_json)
    end
    let!(:publish_subject) { 'DmpUpdater - update DMP ID - BAR' }
    let!(:publish_message) { { action: 'update', provenance: provenance['PK'], dmp: 'BAR' }.to_json }
    let!(:download_subject) { 'DmpUpdater - fetch DMP document - BAR' }
    let!(:download_message) { { provenance: provenance['PK'], dmp: 'BAR', location: 'url' }.to_json }

    it 'returns false if :p_key is nil' do
      expect(described_class._post_process(p_key: nil, json: json)).to be(false)
    end

    it 'returns false if :p_key is an empty string' do
      expect(described_class._post_process(p_key: '', json: json)).to be(false)
    end

    it 'attempts to publish a message to the SNS_PUBLISH_TOPIC' do
      json['dmproadmap_related_identifiers'].first['descriptor'] = 'version_of'
      expect(described_class._post_process(p_key: 'BAR', json: json)).to be(true)
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: publish_subject,
                                                         message: publish_message).once
      expect(sns_client).not_to have_received(:publish).with(topic_arn: 'foo', subject: download_subject,
                                                             message: download_message)
    end

    it 'attempts to publish a message to the SNS_DOWNLOAD_TOPIC' do
      expect(described_class._post_process(p_key: 'BAR', json: json)).to be(true)
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: publish_subject,
                                                         message: publish_message).once
      expect(sns_client).to have_received(:publish).with(topic_arn: 'foo', subject: download_subject,
                                                         message: download_message).once
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  describe '_process_update(updater:, original_version:, new_version:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:mods) { DmpHelper.deep_copy_dmp(obj: dmp) }
    let!(:owner) { dmp_item['dmphub_provenance_id'] }
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}#updater" }

    before do
      mods['title'] = "#{dmp_item['title']} - updated"
    end

    it 'returns nil if :updater is nil' do
      result = described_class._process_update(updater: nil, original_version: dmp_item, new_version: mods)
      expect(result).to be_nil
    end

    it 'returns :original_version if the DMP has been Tombstoned' do
      dmp_item['SK'] = KeyHelper::DMP_TOMBSTONE_VERSION
      result = described_class._process_update(updater: updater, original_version: dmp_item, new_version: mods)
      expect(result).to eql(dmp_item)
    end

    it 'returns nil if :new_version is nil' do
      result = described_class._process_update(updater: updater, original_version: dmp_item, new_version: nil)
      expect(result).to be_nil
    end

    it 'returns the :new_version if :original_version is nil' do
      result = described_class._process_update(updater: updater, original_version: nil, new_version: mods)
      expect(result).to eql(mods)
    end

    it 'returns the :new_version if it is equal to the :old_version' do
      result = described_class._process_update(updater: updater, original_version: dmp_item, new_version: dmp_item)
      expect(result).to eql(dmp_item)
    end

    it 'calls the :splice_for_owner, no :splice_for_others, if the :updater is the :owner' do
      allow(described_class).to receive(:_splice_for_owner)
      allow(described_class).to receive(:_splice_for_others)
      described_class._process_update(updater: owner, original_version: dmp_item, new_version: mods)
      expect(described_class).to have_received(:_splice_for_owner).once
      expect(described_class).not_to have_received(:_splice_for_others)
    end

    it 'calls the :splice_for_others, no :splice_for_owner, if the :updater is NOT the :owner' do
      allow(described_class).to receive(:_splice_for_owner)
      allow(described_class).to receive(:_splice_for_others)
      described_class._process_update(updater: updater, original_version: dmp_item, new_version: mods)
      expect(described_class).not_to have_received(:_splice_for_owner)
      expect(described_class).to have_received(:_splice_for_others).once
    end
  end
end
