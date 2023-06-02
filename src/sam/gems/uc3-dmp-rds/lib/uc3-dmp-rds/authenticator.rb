# frozen_string_literal: true

require 'active_record'
require 'active_record_simple_execute'
require 'json'
require 'mysql2'

module Uc3DmpRds
  # Error from the Rds Adapter
  class AuthenticatorError < StandardError; end

  # Use Rails' ActiveResource to communicate with the DMPHub REST API
  class Authenticator
    MSG_INVALID_TOKEN = 'Invalid user token'
    MSG_INACTIVE_USER = 'User is inactive'

    class << self
      # Look up the user based on the API token. Will fail if Uc3DmpRds::Adapter does not
      # have an established connection!
      def authenticate(token:)
        raise AuthenticatorError, MSG_INVALID_TOKEN if token.nil? || token.to_s.strip.empty?

        users = _query_user(token: token)
        raise AuthenticatorError, MSG_INVALID_TOKEN unless users.is_a?(Array) && users.any?

        user = users.first
        raise AuthenticatorError, MSG_INACTIVE_USER unless user['active']

        _serialize_user(user: user)
      end

      private

      # Query ActiveRecord for the User's record
      def _query_user(token:)
        return nil if token.nil?

        sql = <<~SQL.squish
          SELECT users.id, users.firstname, users.surname, users.email, users.active, i.value orcid,
            orgs.name org_name, ro.name ror_name, ro.ror_id,
            (SELECT perms.name FROM users_perms up LEFT OUTER JOIN perms ON up.perm_id = perms.id
             WHERE users.id = up.user_id AND perms.name = 'modify_templates') perm
          FROM users
            INNER JOIN orgs ON users.org_id = orgs.id
            LEFT OUTER JOIN registry_orgs ro
              ON orgs.id = ro.org_id
            LEFT OUTER JOIN identifiers i
              ON i.identifiable_id = users.id
              AND i.identifiable_type = 'User'
              AND i.identifier_scheme_id IN (SELECT sch.id FROM identifier_schemes sch WHERE sch.name = 'orcid')
          WHERE users.api_token = :token
        SQL
        users = ActiveRecord::Base.simple_execute(sql, token: token.to_s.strip)
      end

      # Convert the ActiveRecord query results into a JSON object
      def _serialize_user(user:)
        return {} if user.nil? || user['email'].nil?

        hash = {
          id: user['id'],
          name: [user['surname'], user['firstname']].join(', '),
          mbox: user['email'],
          admin: !user['perm'].nil?,
          active: user.fetch('active', false)
        }
        hash[:user_id] = { type: 'orcid', identifier: user['orcid'] } unless user['orcid'].nil?
        return hash if user['org_name'].nil?

        hash[:affiliation] = { name: user.fetch('ror_name', user['org_name']) }
        hash[:affiliation][:affiliation_id] = { type: 'ror', identifier: user['ror_id'] } unless user['ror_id'].nil?
        JSON.parse(hash.to_json)
      end
    end
  end
end
