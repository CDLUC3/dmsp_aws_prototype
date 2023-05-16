# frozen_string_literal: true

module Uc3DmpCognito
  class ClientError < StandardError; end

  # Helper functions for working with Dynamo JSON
  class Client
    MSG_MISSING_POOL = 'No Cognito Pool defined. Expecting `ENV[\'COGNITO_USER_POOL\']'
    MSG_COGNITO_ERROR = 'Cognito User Pool Error - %{msg} - %{trace}'

    class << self
      # Fetch the name of the client from the client id provided.
      # DMP Provenance names match the Cognito client names
      def get_client_name(client_id:)
        user_pool_id = ENV.fetch('COGNITO_USER_POOL', nil)
        raise ClientError, MSG_MISSING_POOL if user_pool_id.nil?

        client = Aws::CognitoIdentityProvider::Client.new(region: ENV.fetch('AWS_REGION', nil))
        resp = client.describe_user_pool_client({ user_pool_id: user_pool_id, client_id: client_id })
        resp&.user_pool_client&.client_name&.downcase
      rescue Aws::Errors::ServiceError => e
        raise ClientError, format(MSG_COGNITO_ERROR, msg: e.message, trace: e.backtrace)
      end
    end
  end
end
