# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpCognito::Client' do
  let!(:described_class) { Uc3DmpCognito::Client }
  let!(:client_err) { Uc3DmpCognito::ClientError }

  describe 'get_client_name(client_id:)' do
    it 'raises an error if the user pool is not set in the ENV' do
      ENV.delete('COGNITO_USER_POOL')
      msg = Uc3DmpCognito::Client::MSG_MISSING_POOL
      expect { described_class.get_client_name(client_id: nil) }.to raise_error(client_err, msg)
    end

    it 'returns the client name for the given :client_id' do
      ENV['COGNITO_USER_POOL'] = 'test-pool'
      mock_cognito(name: 'bar')
      expect(described_class.get_client_name(client_id: '12345')).to eql('bar')
    end

    it 'handles Aws::Errors::ServiceError properly' do
      ENV['COGNITO_USER_POOL'] = 'test-pool'
      mock_cognito(success: false)
      expect { described_class.get_client_name(client_id: 'foo') }.to raise_error(client_err)
    end
  end
end
