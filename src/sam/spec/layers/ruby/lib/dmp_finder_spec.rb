# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DmpFinder' do
  let!(:described_class) do
    DmpFinder.new(
      provenance: JSON.parse({ PK: "#{KeyHelper::PK_DMP_PREFIX}foo" }.to_json),
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

  describe 'dmps_for_provenance' do
    it 'returns a 403 error if the :provenance was not set during initialization' do
      clazz = DmpFinder.new
      result = clazz.dmps_for_provenance
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an empty array if the provenance has no DMPs' do
      result = described_class.dmps_for_provenance
      expect(result[:status]).to be(200)
      expect(result[:items]).to eql([])
    end

    it 'returns an array of the provenance\'s DMPs' do
      resp = DynamoResponse.new([DynamoItem.new(dmp['dmp'])])
      allow_any_instance_of(DynamoClient).to receive(:query).and_return(resp)
      result = described_class.dmps_for_provenance
      expect(result[:status]).to be(200)
      expect(result[:items].is_a?(Array)).to be(true)
      expect(result[:items].length).to be(1)
      expect(result[:items].first).to eql(dmp)
    end

    it 'returns a 500 error if Dynamo throws an error' do
      allow_any_instance_of(DynamoClient).to receive(:query).and_raise(aws_error)
      result = described_class.dmps_for_provenance
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end
  end

  describe 'find_dmp_by_json(json:)' do
    it 'returns a 400 error if :json is nil' do
      result = described_class.find_dmp_by_json(json: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 400 error if the :json does not contain a :PK or :dmp_id' do
      dmp['dmp'].delete('PK')
      dmp['dmp'].delete('dmp_id')
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns the DMP by its :PK' do
      expected = { status: 200, items: [dmp] }
      allow(described_class).to receive(:find_dmp_by_pk).and_return(expected)
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
      expect(result[:items].first).to eql(dmp)
    end

    it 'returns the DMP by its :dmphub_provenance_identifier' do
      allow(described_class).to receive(:find_dmp_by_pk).and_return({ status: 404, items: [] })
      expected = { status: 200, items: [dmp] }
      allow(described_class).to receive(:find_dmp_by_dmphub_provenance_identifier).and_return(expected)
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
      expect(result[:items].first).to eql(dmp)
    end

    it 'returns a 404 error if the DMP could not be found' do
      fail_response = { status: 404, error: Messages::MSG_DMP_NOT_FOUND }
      allow(described_class).to receive(:find_dmp_by_pk).and_return(fail_response)
      allow(described_class).to receive(:find_dmp_by_dmphub_provenance_identifier).and_return(fail_response)
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns a 500 error if :find_dmp_by_pk returns a 500' do
      fail_response = { status: 500, error: Messages::MSG_SERVER_ERROR }
      allow(described_class).to receive(:find_dmp_by_pk).and_return(fail_response)
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end

    it 'returns a 500 error if :find_dmp_by_dmphub_provenance_identifier returns a 500' do
      fail_response = { status: 500, error: Messages::MSG_SERVER_ERROR }
      allow(described_class).to receive(:find_dmp_by_pk).and_return({ status: 404, items: [] })
      allow(described_class).to receive(:find_dmp_by_dmphub_provenance_identifier).and_return(fail_response)
      result = described_class.find_dmp_by_json(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
    end
  end

  describe 'find_dmp_by_pk(p_key:, s_key:)' do
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}#foo" }

    it 'returns a 404 error if the :p_key is nil' do
      result = described_class.find_dmp_by_pk(p_key: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 404 error if the :p_key had no match in the database' do
      result = described_class.find_dmp_by_pk(p_key: pk)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    # TODO: API should test whether or not it returns the latest version
    it 'returns the DMP' do
      resp = DynamoResponse.new([], JSON.parse({ PK: 'foo' }.to_json))
      allow_any_instance_of(DynamoClient).to receive(:get_item).and_return(resp)
      result = described_class.find_dmp_by_pk(p_key: pk)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
      expect(result[:items].first['dmp']['PK']).to eql('foo')
    end

    it 'returns a 500 error if Dynamo throws an error' do
      allow_any_instance_of(DynamoClient).to receive(:get_item).and_raise(aws_error)
      result = described_class.find_dmp_by_pk(p_key: pk)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end
  end

  describe 'find_dmp_versions(p_key:)' do
    let!(:pk) { "#{KeyHelper::PK_DMP_PREFIX}#foo" }

    it 'returns a 404 error if the :p_key is nil' do
      result = described_class.find_dmp_versions(p_key: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 404 error if the :p_key had no match in the database' do
      result = described_class.find_dmp_versions(p_key: pk)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns the DMP' do
      resp = DynamoResponse.new([DynamoItem.new(JSON.parse({ PK: 'foo' }.to_json))])
      allow_any_instance_of(DynamoClient).to receive(:query).and_return(resp)
      result = described_class.find_dmp_versions(p_key: pk)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
    end

    it 'returns a 500 error if Dynamo throws an error' do
      allow_any_instance_of(DynamoClient).to receive(:query).and_raise(aws_error)
      result = described_class.find_dmp_versions(p_key: pk)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end
  end

  describe 'find_dmp_by_dmphub_provenance_identifier(json:)' do
    let!(:dmp) { JSON.parse({ title: 'Just testing', dmp_id: { type: 'doi', identifier: 'foo' } }.to_json) }

    it 'returns a 400 if :json is nil' do
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: nil)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 400 if :json contains no :dmp_id' do
      dmp = JSON.parse({ title: 'Just testing' }.to_json)
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: dmp)
      expect(result[:status]).to be(400)
      expect(result[:error].start_with?(Messages::MSG_INVALID_ARGS)).to be(true)
    end

    it 'returns a 500 if the DynamoDB query fails' do
      allow_any_instance_of(DynamoClient).to receive(:query).and_raise(aws_error)
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: dmp)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns a 404 if the query found no matches' do
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: dmp)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_DMP_NOT_FOUND)
    end

    it 'returns a 404 if the query returned a match but the subsequent find_dmp_by_pk did not' do
      resp = DynamoResponse.new([DynamoItem.new(JSON.parse({ PK: 'foo' }.to_json))])
      allow_any_instance_of(DynamoClient).to receive(:query).and_return(resp)
      allow(described_class).to receive(:find_dmp_by_pk).and_return({ status: 404, items: [] })
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: dmp)
      expect(result[:status]).to be(404)
      expect(result[:items]).to eql([])
    end

    it 'returns the expected DMP' do
      resp = DynamoResponse.new([DynamoItem.new(dmp)])
      allow_any_instance_of(DynamoClient).to receive(:query).and_return(resp)
      allow(described_class).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
      result = described_class.find_dmp_by_dmphub_provenance_identifier(json: dmp)
      expect(result[:status]).to be(200)
      expect(result[:items].length).to be(1)
      expect(result[:items].first).to eql(dmp)
    end
  end

  describe 'append_versions(p_key:, dmp:)' do
    let!(:json) { dmp['dmp'] }
    let!(:p_key) { json['PK'] }

    it 'returns the :dmp as-is if :p_key is nil' do
      expect(described_class.append_versions(p_key: nil, dmp: json)).to eql(json)
    end

    it 'returns the :dmp as-is if :dmp is not a Hash' do
      expect(described_class.append_versions(p_key: p_key, dmp: 'foo')).to eql('foo')
    end

    it 'returns the :dmp as-is if :find_dmp_versions does not return a 200' do
      allow(described_class).to receive(:find_dmp_versions).and_return({ status: 404 })
      expect(described_class.append_versions(p_key: p_key, dmp: json)).to eql(json)
    end

    it 'does not return the :dmphub_versions array if there is only one version' do
      allow(described_class).to receive(:find_dmp_versions).and_return({ status: 200, items: [json] })
      url = 'https://api.example.com/v0'
      mock_ssm(value: url)
      expect(described_class.append_versions(p_key: p_key, dmp: json)['dmphub_versions']).to be(nil)
    end

    # rubocop:disable RSpec/ExampleLength
    it 'returns the :dmphub_versions array if there are multiple versions' do
      prior = json.clone
      timestamp = '2020-01-01T01:02:03+00:00'
      prior['SK'] = "#{KeyHelper::SK_DMP_PREFIX}#{timestamp}"
      prior['modified'] = timestamp
      prior['created'] = timestamp
      prior['modified'] = timestamp
      prior['dmphub_modification_day'] = timestamp.split('T').first

      allow(described_class).to receive(:find_dmp_versions).and_return({ status: 200, items: [json, prior] })
      url = 'https://api.example.com/v0'
      mock_ssm(value: url)
      expected = JSON.parse([
        {
          timestamp: json['modified'],
          url: "#{url}/dmps/#{p_key.gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{json['modified']}"
        },
        {
          timestamp: timestamp,
          url: "#{url}/dmps/#{p_key.gsub(KeyHelper::PK_DMP_PREFIX, '')}?version=#{timestamp}"
        }
      ].to_json)
      expect(described_class.append_versions(p_key: p_key, dmp: json)['dmphub_versions']).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
