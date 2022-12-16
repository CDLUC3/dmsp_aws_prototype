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

  describe '_version_it(dmp:)' do
    let!(:dmp_item) { dmp['dmp'] }

    before do
      dmp_item['SK'] = KeyHelper::DMP_LATEST_VERSION
      dmp_item['dmphub_updated_at'] = '2022-09-20T11:50:34+1'
    end

    it 'returns 400 if :dmp is nil' do
      result = described_class._version_it(dmp: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns 400 if :PK is nil' do
      dmp_item.delete('PK')
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns 400 if :PK is NOT for a DMP' do
      dmp_item['PK'] = "#{KeyHelper::PK_PROVENANCE_PREFIX}foo"
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns 403 if :SK is NOT the latest version' do
      dmp_item['SK'] = "#{KeyHelper::SK_DMP_PREFIX}2022-09-01"
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_NO_HISTORICALS)
    end

    it 'returns 404 if the DynamoDB update fails' do
      allow_any_instance_of(DynamoResponse).to receive(:successful?).and_return(false)
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns 500 if AWS throws an error' do
      allow_any_instance_of(DynamoClient).to receive(:put_item).and_raise(aws_error)
      allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'versions the :dmp and returns true' do
      version = DmpHelper.deep_copy_dmp(obj: dmp_item)
      version['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{dmp_item['dmphub_updated_at']}"
      version['dmproadmap_related_identifiers'] = [{
        descriptor: 'is_previous_version_of',
        work_type: 'dmp',
        type: 'doi',
        identifier: dmp_item.fetch('dmp_id', {})['identifier']
      }]
      resp = DynamoResponse.new([DynamoItem.new(version)])
      allow_any_instance_of(DynamoClient).to receive(:update_item).and_return(resp)
      result = described_class._version_it(dmp: dmp_item)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
      expect(result[:items].first['PK']).to eql(dmp_item['PK'])
      expect(result[:items].first['SK']).to eql("#{KeyHelper::SK_DMP_PREFIX}#{dmp_item['dmphub_updated_at']}")
      ids = result[:items].first['dmproadmap_related_identifiers']
      current = ids.select { |id| id['descriptor'] == 'is_previous_version_of' }.first
      expect(current['descriptor']).to eql('is_previous_version_of')
      expect(current['work_type']).to eql('output_management_plan')
      expect(current['type']).to eql('doi')
      expect(current['identifier']).to eql(dmp_item['dmp_id']['identifier'])
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

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

  describe 'def _append_version_url(json:, old_version:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:old_version) { DmpHelper.deep_copy_dmp(obj: dmp_item) }

    before do
      old_version['SK'] = "#{KeyHelper::SK_DMP_PREFIX}2022-01-01T11:20:09+1"
      old_version['title'] = 'old foo test'
    end

    it 'returns the :json as-is if it is not a Hash' do
      result = described_class._append_version_url(json: 'foo', old_version: old_version)
      expect(result).to eql('foo')
    end

    it 'returns the :json as-is if the :old_version is not a Hash' do
      result = described_class._append_version_url(json: dmp_item, old_version: 'foo')
      expect(result).to eql(dmp_item)
    end

    it 'returns the :json as-is if :old_version does not have an SK' do
      old_version.delete('SK')
      result = described_class._append_version_url(json: dmp_item, old_version: old_version)
      expect(result).to eql(dmp_item)
    end

    it 'initializes the :dmproadmap_related_identifiers attribute' do
      dmp_item.delete('dmproadmap_related_identifiers')
      result = described_class._append_version_url(json: dmp_item, old_version: old_version)
      expect(result['dmproadmap_related_identifiers'].length).to be(1)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'appends the version to the :dmproadmap_related_identifiers attribute' do
      dmp_item['dmproadmap_related_identifiers'] = [] if dmp_item['dmproadmap_related_identifiers'].nil?
      existing = JSON.parse({
        descriptor: 'cites', work_type: 'dataset', type: 'url', identifier: 'http://foo.org'
      }.to_json)
      dmp_item['dmproadmap_related_identifiers'] << existing
      result = described_class._append_version_url(json: dmp_item, old_version: old_version)
      version = "?version=#{old_version['SK'].gsub(KeyHelper::SK_DMP_PREFIX, '')}"
      expect(result['dmproadmap_related_identifiers'].include?(existing)).to be(true)
      identifiers = result['dmproadmap_related_identifiers'].select do |id|
        id['identifier'].include?(version)
      end
      expect(identifiers.first['descriptor']).to eql('is_new_version_of')
      expect(identifiers.first['work_type']).to eql('output_management_plan')
      expect(identifiers.first['type']).to eql('url')
      expect(identifiers.first['identifier'].end_with?(version)).to be(true)
    end
    # rubocop:enable RSpec/ExampleLength
  end

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

  describe '_splice_for_owner(owner:, updater:, base:, mods:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:owner) { "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" }
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:mods) do
      JSON.parse({
        project: [
          funding: [{
            name: 'new_funder',
            funder_id: { type: 'url', identifier: 'http://new.org' },
            funding_status: 'applied'
          }]
        ],
        dmproadmap_related_identifiers: [
          { type: 'url', work_type: 'software', descriptor: 'references', identifier: 'http://github.com' }
        ]
      }.to_json)
    end

    before do
      dmp_item['dmphub_provenance_id'] = owner
    end

    it 'returns :base if :owner is nil' do
      expect(described_class._splice_for_owner(owner: nil, updater: updater, base: dmp_item,
                                               mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :updater is nil' do
      expect(described_class._splice_for_owner(owner: updater, updater: nil, base: dmp_item,
                                               mods: mods)).to eql(dmp_item)
    end

    it 'returns :mods if :base is nil' do
      expect(described_class._splice_for_owner(owner: owner, updater: updater, base: nil, mods: mods)).to eql(mods)
    end

    it 'returns :base if :mods is nil' do
      expect(described_class._splice_for_owner(owner: owner, updater: updater, base: dmp_item,
                                               mods: nil)).to eql(dmp_item)
    end

    it 'retains other system\'s metadata' do
      # funds and related identifiers that are not owned by the system of provenance have a provenance_id
      funds = dmp_item['project'].first['funding'].reject { |fund| fund['dmphub_provenance_id'].nil? }
      ids = dmp_item['dmproadmap_related_identifiers'].reject { |id| id['dmphub_provenance_id'].nil? }
      result = described_class._splice_for_owner(owner: owner, updater: updater, base: dmp_item, mods: mods)
      funds.each { |fund| expect(result['project'].first['funding'].include?(fund)).to be(true) }
      ids.each { |id| expect(result['dmproadmap_related_identifiers'].include?(id)).to be(true) }
    end

    it 'uses the :mods if :base has no :project defined' do
      dmp_item.delete('project')
      result = described_class._splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['project']).to eql(mods['project'])
    end

    it 'uses the :mods if :base has no :funding defined' do
      dmp_item['project'].first.delete('funding')
      result = described_class._splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['project'].first['funding']).to eql(mods['project'].first['funding'])
    end

    it 'updates the :funding' do
      result = described_class._splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      funds = dmp_item['project'].first['funding'].reject { |fund| fund['dmphub_provenance_id'].nil? }
      expected = mods['project'].first['funding'].length + funds.length
      expect(result['project'].first['funding'].length).to eql(expected)
      mods['project'].first['funding'].each do |fund|
        expect(result['project'].first['funding'].include?(fund)).to be(true)
      end
    end

    it 'updates the :dmproadmap_related_identifiers' do
      result = described_class._splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      ids = dmp_item['dmproadmap_related_identifiers'].reject { |id| id['dmphub_provenance_id'].nil? }
      expected = mods['dmproadmap_related_identifiers'].length + ids.length
      expect(result['dmproadmap_related_identifiers'].length).to eql(expected)
      mods['dmproadmap_related_identifiers'].each do |id|
        expect(result['dmproadmap_related_identifiers'].include?(id)).to be(true)
      end
    end

    it 'uses the :mods if :base has no :dmproadmap_related_identifiers defined' do
      dmp_item.delete('dmproadmap_related_identifiers')
      result = described_class._splice_for_owner(owner: owner, updater: owner, base: dmp_item, mods: mods)
      expect(result['dmproadmap_related_identifiers']).to eql(mods['dmproadmap_related_identifiers'])
    end
  end

  describe '_splice_for_others(owner:, updater:, base:, mods:)' do
    let!(:dmp_item) { dmp['dmp'] }
    let!(:owner) { "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" }
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:mods) do
      JSON.parse({
        project: [
          funding: [{
            name: 'new_funder',
            funder_id: { type: 'url', identifier: 'http://new.org' },
            funding_status: 'applied'
          }]
        ],
        dmproadmap_related_identifiers: [
          { type: 'url', work_type: 'software', descriptor: 'references', identifier: 'http://github.com' }
        ]
      }.to_json)
    end

    before do
      dmp_item['dmphub_provenance_id'] = owner
    end

    it 'returns :base if :owner is nil' do
      expect(described_class._splice_for_others(owner: nil, updater: updater, base: dmp_item,
                                                mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :updater is nil' do
      expect(described_class._splice_for_others(owner: owner, updater: nil, base: dmp_item,
                                                mods: mods)).to eql(dmp_item)
    end

    it 'returns :base if :base is nil' do
      expect(described_class._splice_for_others(owner: owner, updater: updater, base: nil, mods: mods)).to be_nil
    end

    it 'returns :base if :mods is nil' do
      expect(described_class._splice_for_others(owner: owner, updater: updater, base: dmp_item,
                                                mods: nil)).to eql(dmp_item)
    end

    it 'updates the :funding' do
      result = described_class._splice_for_others(owner: owner, updater: updater, base: dmp_item, mods: mods)
      expected = dmp_item['project'].first['funding'].length + 1
      expect(result['project'].first['funding'].length).to eql(expected)
    end

    it 'updates the :dmproadmap_related_identifiers' do
      result = described_class._splice_for_others(owner: owner, updater: updater, base: dmp_item, mods: mods)
      expected = dmp_item['dmproadmap_related_identifiers'].length + 1
      expect(result['dmproadmap_related_identifiers'].length).to eql(expected)
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '_update_funding(updater:, base:, mods:)' do
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:funder_id) { { type: 'ror', identifier: 'https://ror.org/12345' } }
    let!(:other_funder_id) { { type: 'ror', identifier: 'https://ror.org/09876' } }
    let!(:other_existing) { 'http://other.org/grants/333' }
    let!(:owner_existing) { 'http://owner.com/grants/123' }
    let!(:base) do
      JSON.parse([
        # System of provenance fundings
        { name: 'name-only', funding_status: 'applied' },
        { name: 'planned', funder_id: funder_id, funding_status: 'planned' },
        { name: 'granted', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'url', identifier: owner_existing } },

        # Other non-system of provenance fundings
        { name: 'name-only', funding_status: 'applied', dmphub_created_at: Time.now.iso8601,
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other" },
        { name: 'rejected', funder_id: other_funder_id, funding_status: 'rejected',
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other",
          dmphub_created_at: Time.now.iso8601 },
        { name: 'granted', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'url', identifier: other_existing },
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}other",
          dmphub_created_at: Time.now.iso8601 }
      ].to_json)
    end

    it 'returns :base if the :updater is nil' do
      result = described_class._update_funding(updater: nil, base: base, mods: {})
      expect(result).to eql(base)
    end

    it 'returns :base if the :mods are empty' do
      result = described_class._update_funding(updater: updater, base: base, mods: nil)
      expect(result).to eql(base)
    end

    it 'returns the :mods if :base is nil' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      result = described_class._update_funding(updater: updater, base: nil, mods: mods)
      expect(result.length).to be(1)
      expect(result).to eql(mods)
    end

    it 'ignores entries that do not include the :funding_status or :grant_id' do
      mods = JSON.parse([
        { name: 'ignorable', funder_id: { type: 'url', identifier: 'http:/skip.me' } }
      ].to_json)
      result = described_class._update_funding(updater: updater, base: base, mods: mods)
      expect(result.length).to eql(base.length)
    end

    it 'does not delete other systems\' entries' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      result = described_class._update_funding(updater: updater, base: base, mods: mods)
      expect(result.length).to eql(base.length + 1)
      expect(result).to eql(base + mods)
    end

    it 'appends new entries' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' }, funding_status: 'planned' }
      ].to_json)
      results = described_class._update_funding(updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['name'] == mods.first['name'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(mods.first['funder_id'])
      expect(result['funding_status']).to eql(mods.first['funding_status'])
      expect(result['grant_id'].nil?).to be(true)
    end

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'includes dmphub metadata when the new entry includes a :grant_id' do
      mods = JSON.parse([
        { name: 'new', funder_id: { type: 'url', identifier: 'http:/keep.me' },
          funding_status: 'granted', grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class._update_funding(updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['name'] == mods.first['name'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(mods.first['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'updates the latest provenance system entry with grant metadata' do
      mods = JSON.parse([
        { name: 'arbitrary', funder_id: funder_id, funding_status: 'granted',
          grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class._update_funding(updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.last
      original = base.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.first

      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(original['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it 'adds a new entry if the DMP already has a \'rejected\' or \'granted\' entry for the funder' do
      mods = JSON.parse([
        { name: 'arbitrary', funder_id: other_funder_id, funding_status: 'granted',
          grant_id: { type: 'other', identifier: '4444' } }
      ].to_json)
      results = described_class._update_funding(updater: updater, base: base, mods: mods)
      result = results.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.last
      original = base.select { |entry| entry['funder_id'] == mods.first['funder_id'] }.first
      expect(result.nil?).to be(false)
      expect(result['funder_id']).to eql(original['funder_id'])
      expect(result['funding_status']).to eql('granted')
      expect(result['grant_id']['type']).to eql(mods.first['grant_id']['type'])
      expect(result['grant_id']['identifier']).to eql(mods.first['grant_id']['identifier'])
      expect(result['grant_id']['dmphub_created_at'].nil?).to be(false)
      expect(result['grant_id']['dmphub_provenance_id']).to eql(updater)
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # rubocop:disable RSpec/MultipleMemoizedHelpers
  describe '_update_related_identifiers(updater:, base:, mods:)' do
    let!(:updater) { "#{KeyHelper::PK_PROVENANCE_PREFIX}bar" }
    let!(:updater_existing) { 'http://33.11111/foo' }
    let!(:owner_existing) { 'http://owner.com' }
    let!(:other_existing) { 'http://33.22222/bar' }
    let!(:base) do
      JSON.parse([
        { descriptor: 'cites', work_type: 'software', type: 'url',
          identifier: owner_existing },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: other_existing,
          dmphub_provenance_id: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: updater_existing, dmphub_provenance_id: updater }
      ].to_json)
    end
    let!(:mods) do
      JSON.parse([
        { descriptor: 'cites', work_type: 'software', type: 'url',
          identifier: 'http://github.com/new' },
        { descriptor: 'cites', work_type: 'dataset', type: 'doi',
          identifier: 'http://33.22222/new' }
      ].to_json)
    end

    it 'returns :base if the :updater is nil' do
      result = described_class._update_related_identifiers(updater: nil, base: base, mods: mods)
      expect(result).to eql(base)
    end

    it 'returns :base if the :mods are empty' do
      result = described_class._update_related_identifiers(updater: updater, base: base, mods: nil)
      expect(result).to eql(base)
    end

    it 'returns :mods if the :base is nil' do
      result = described_class._update_related_identifiers(updater: updater, base: nil, mods: mods)
      mods.each { |mod| mod['dmphub_provenance_id'] = updater }
      expect(result).to eql(mods)
    end

    it 'removes existing entries for the updater' do
      result = described_class._update_related_identifiers(updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == updater_existing }.length).to be(0)
    end

    it 'does NOT remove entries for other systems' do
      result = described_class._update_related_identifiers(updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == other_existing }.length).to be(1)
    end

    it 'does NOT remove entries for the system of provenance' do
      result = described_class._update_related_identifiers(updater: updater, base: base, mods: mods)
      expect(result.select { |i| i['identifier'] == owner_existing }.length).to be(1)
    end

    it 'adds the updater\'s entries' do
      result = described_class._update_related_identifiers(updater: updater, base: base, mods: mods)
      updated = result.select { |i| i['dmphub_provenance_id'] == updater }
      expect(updated.length).to be(2)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
