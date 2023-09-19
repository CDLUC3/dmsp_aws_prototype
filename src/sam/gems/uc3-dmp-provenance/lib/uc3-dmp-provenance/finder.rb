# frozen_string_literal: true

require 'uc3-dmp-cognito'
require 'uc3-dmp-dynamo'

module Uc3DmpProvenance
  # Standard Error Message from Uc3DmpProvenance
  class FinderError < StandardError; end

  # Helper for fetching Provenance JSON records
  class Finder
    class << self
      # Get the Provenance item for the Lambda :event
      #
      # Expecting the :claims hash from the requestContext[:authorizer] portion of the :event.
      # It should look something like this:
      #  {
      #    "sub": "abcdefghijklmnopqrstuvwxyz",
      #    "token_use": "access",
      #    "scope": "https://auth.dmphub-dev.cdlib.org/dev.write",
      #    "auth_time": "1675895546",
      #    "iss": "https://cognito-idp.us-west-2.amazonaws.com/us-west-A_123456",
      #    "exp": "Wed Feb 08 22:42:26 UTC 2023",
      #    "iat": "Wed Feb 08 22:32:26 UTC 2023",
      #    "version": "2",
      #    "jti": "5d3be8a7-c595-1111-yyyy-xxxxxxxxxx",
      #    "client_id": "abcdefghijklmnopqrstuvwxyz"
      #  }
      # -------------------------------------------------------------------------------------------
      def from_lambda_cotext(identity:, client: nil, logger: nil)
        return nil unless identity.is_a?(Hash) && !identity['iss'].nil? && !identity['client_id'].nil?

        client = client.nil? ? Uc3DmpDynamo::Client.new : client
        client_name = _cognito_client_id_to_name(claim: identity, logger: logger)

        resp = client.get_item(
          key: { PK: Helper.append_pk_prefix(provenance: client_name), SK: Helper::SK_PROVENANCE_PREFIX },
          logger: logger
        )
        resp.nil? || resp.empty? ? nil : resp
      end

      # Fetch the Provenance by it's PK.
      #
      # Expecting either the name (e.g. `dmptool` or the qualified PK (e.g. `PROVENANCE#dmptool`)
      def from_pk(pk:, logger: nil)
        return nil if pk.nil?

        pk = Helper.append_pk_prefix(provenance: pk)
        resp = client.get_item(
          key: { PK: Helper.append_pk_prefix(provenance: pk), SK: Helper::SK_PROVENANCE_PREFIX },
          logger: logger
        )
        resp.nil? || resp.empty? ? nil : resp
      end

      private

      # Method to fetch the client's name from the Cognito UserPool based on the client_id
      def _cognito_client_id_to_name(claim:, logger: nil)
        return nil if claim.nil? || !claim.is_a?(Hash) || claim['iss'].nil? || claim['client_id'].nil?

        user_pool_id = claim['iss'].split('/').last
        logger.debug(message: "Cognito User Pool: #{user_pool_id}, ClientId: #{claim['client_id']}") if logger.respond_to?(:debug)
        Uc3DmpCognito::Client.get_client_name(client_id: claim['client_id'])
      end
    end
  end
end
