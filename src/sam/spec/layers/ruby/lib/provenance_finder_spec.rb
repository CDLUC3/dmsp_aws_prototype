# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ProvenanceFinder' do
  let!(:described_class) do
    ProvenanceFinder.new(
      table_name: 'bar',
      client: mock_dynamodb(item_array: []),
      debug_mode: false
    )
  end

  let!(:identity) { JSON.parse({ cognitoIdentityId: 'foo' }.to_json) }

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
  end

  describe 'provenance_from_lambda_cotext(identity:)' do
    it 'returns a 403 if :identity is not a Hash' do
      result = described_class.provenance_from_lambda_cotext(identity: 'foo')
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an 403 if :identity does not contain a :cognitoIdentityId' do
      result = described_class.provenance_from_lambda_cotext(identity: JSON.parse({ foo: 'bar' }.to_json))
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an empty Hash if no matching provenance record is found' do
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_PROVENANCE_NOT_FOUND)
    end

    it 'calls log_error and returns an empty Hash if an Amazon error is thrown' do
      allow_any_instance_of(DynamoClient).to receive(:get_item).and_raise(aws_error)
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns the provenance record' do
      rec = {
        PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}#foo",
        SK: KeyHelper::SK_PROVENANCE_PREFIX
      }
      mock_dynamodb(item_array: [rec])
      resp = DynamoResponse.new([], JSON.parse(rec.to_json))
      allow_any_instance_of(DynamoClient).to receive(:get_item).and_return(resp)
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(200)
      expect(result[:items].first).to eql(JSON.parse(rec.to_json))
    end
  end
end
