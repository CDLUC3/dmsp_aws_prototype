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

  let!(:identity) do
    JSON.parse(
      {
        sub: 'abcdefghijklmnopqrstuvwxyz',
        token_use: 'access',
        scope: 'https://auth.dmphub-dev.cdlib.org/dev.write',
        auth_time: '1675895546',
        iss: 'https://cognito-idp.us-west-2.amazonaws.com/us-west-A_123456',
        exp: 'Wed Feb 08 22:42:26 UTC 2023',
        iat: 'Wed Feb 08 22:32:26 UTC 2023',
        version: '2',
        jti: 'abc12345-b123-1111-yyyy-xxxxxxxxxx',
        client_id: 'abcdefghijklmnopqrstuvwxyz'
      }.to_json
    )
  end

  before do
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
  end

  describe 'provenance_from_lambda_cotext(identity:)' do
    it 'returns a 403 if :identity is not a Hash' do
      result = described_class.provenance_from_lambda_cotext(identity: 'foo')
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an 403 if :identity does not contain a :iss' do
      identity.delete('iss')
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an 403 if :identity does not contain a :client_id' do
      identity.delete('client_id')
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(403)
      expect(result[:error]).to eql(Messages::MSG_DMP_FORBIDDEN)
    end

    it 'returns an empty Hash if no matching provenance record is found' do
      allow(described_class).to receive(:client_id_to_name).and_return('foo')
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(404)
      expect(result[:error]).to eql(Messages::MSG_PROVENANCE_NOT_FOUND)
    end

    it 'calls log_error and returns an empty Hash if an Amazon error is thrown' do
      allow(described_class).to receive(:client_id_to_name).and_return('foo')
      described_class.client = mock_dynamodb(item_array: [], success: false)
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(500)
      expect(result[:error]).to eql(Messages::MSG_SERVER_ERROR)
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns the provenance record' do
      allow(described_class).to receive(:client_id_to_name).and_return('foo')
      rec = {
        PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}#foo",
        SK: KeyHelper::SK_PROVENANCE_PREFIX
      }
      described_class.client = mock_dynamodb(item_array: [rec], success: true)
      resp = DynamoResponse.new([], JSON.parse(rec.to_json))
      allow_any_instance_of(DynamoClient).to receive(:get_item).and_return(resp)
      result = described_class.provenance_from_lambda_cotext(identity: identity)
      expect(result[:status]).to be(200)
      expect(result[:items].first).to eql(JSON.parse(rec.to_json))
    end
  end

  describe 'client_id_to_name(claim:)' do
    it 'returns nil if :claim is not a Hash' do
      expect(described_class.client_id_to_name(claim: [])).to eql(nil)
    end

    it 'returns nil if :claim[:iss] is not present' do
      identity.delete('iss')
      expect(described_class.client_id_to_name(claim: identity)).to eql(nil)
    end

    it 'returns nil if :claim[:client_id] is not present' do
      identity.delete('client_id')
      expect(described_class.client_id_to_name(claim: identity)).to eql(nil)
    end

    it 'logs an error and returns nil if Cognito throws an error' do
      mock_cognito(success: false)
      expect(described_class.client_id_to_name(claim: identity)).to be_nil
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns the provenance name' do
      mock_cognito(success: true)
      allow_any_instance_of(CognitoUserPool).to receive(:client_name).and_return('foo')
      expect(described_class.client_id_to_name(claim: identity)).to eql('foo')
    end
  end
end
