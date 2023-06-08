# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-rds'

module Functions
  # The handler for POST /dmps/validate
  class UserTokenAuth
    SOURCE = 'LambdaAuthorizer: AdminTokenAuth'

    MSG_INVALID_TOKEN = 'Invalid or expired token'
    MSG_INACTIVE_USER = 'Locked or inactive user account'

    # Parameters
    # ----------
    # event: Hash, required
    #     API Gateway Lambda Proxy Input Format
    #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

    # Returns
    # ------
    # API Gateway Lambda Proxy Output Format: dict
    #     'statusCode' and 'body' are required
    #     # api-gateway-simple-proxy-for-lambda-output-format
    #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      def process(event:, context:)
        # Only process if there is a valid API token
        typ = event.fetch('type', 'TOKEN')
        token_hdr = event.fetch('authorizationToken', '')
        method = event.fetch('methodArn', '')
        parts = token_hdr.split(' ')
        continue = typ.to_s.downcase == 'token' && token_hdr.is_a?(String) && !token_hdr.strip.empty? &&
                   method.is_a?(String) && method.start_with?('arn:aws:execute-api') &&
                   parts.length == 2 && parts.first.downcase == 'bearer'
        method = _genericize_arn(method_arn: method) if continue
        return _generateDenial(token: token, msg: MSG_INVALID_TOKEN, resource: method) unless continue

        # Debug, output the incoming Event and Context
        debug = Uc3DmpApiCore::SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        # Connect to the DB
        connected = _establish_connection
        return _generateDenial(token: token, msg: Uc3DmpApiCore::MSG_SERVER_ERROR, resource: method) unless connected

        # Fetch the user based on the API token
        token = parts.last
        user = Uc3DmpRds::Authenticator.authenticate(token: token)

        # Deny access unless the user is an admin and their account is active
        return _generateDenial(token: token, msg: MSG_INACTIVE_USER, resource: method) unless user['active']

        _generatePolicy(token: token, principal: user, resource: method)
      rescue Aws::Errors::ServiceError => e
        Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        'Error: Unable to validate token'
        _generateDenial(token: token, msg: e.message, resource: method)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        _generateDenial(token: token, msg: Uc3DmpApiCore::MSG_SERVER_ERROR, resource: method)
      end

      private

      # Generate an IAM policy so the User can invoke the API endpoint
      def _generatePolicy(token:, principal:, resource:)
        affiliation = principal.fetch('affiliation', {})
        context = {
          id: principal['id'],
          name: principal.fetch('name', '').to_s,
          mbox: principal.fetch('mbox', '').to_s,
          admin: principal.fetch('admin', false)
        }
        context[:token] = principal['token'] unless principal['token'].nil?
        context[:orcid] = principal.fetch('user_id', {})['identifier'] unless principal['user_id'].nil?
        context[:affiliation] = affiliation['name'] unless affiliation['name'].nil?
        context[:affiliation_id] = affiliation.fetch('affiliation_id', {})['identifier'] unless affiliation['affiliation_id'].nil?

        JSON.parse({
          principalId: token.to_s,
          usageIdentifierKey: token.to_s,
          policyDocument: {
            Version: '2012-10-17',
            Statement: [{
              Action: 'execute-api:Invoke',
              Effect: 'Allow',
              Resource: [resource.to_s, "#{resource.to_s}/*"]
            }]
          },
          context: context
        }.to_json)
      end

      # Generate an IAM policy so the User CAN NOT invoke the API endpoint
      def _generateDenial(token:, msg:, resource:)
        JSON.parse({
          principalId: token.to_s,
          usageIdentifierKey: token.to_s,
          policyDocument: {
            Version: '2012-10-17',
            Statement: [{
              Action: 'execute-api:Invoke',
              Effect: 'Deny',
              Resource: [resource.to_s, "#{resource.to_s}/*"]
            }]
          },
          context: { error: msg }
        }.to_json)
      end

      def _genericize_arn(method_arn:)
        # We need to wildcard everything after the HTTP Method in the resoource ARN because API Gateway
        # caches the policy. So, if the user authenticates for `GET /wips` it will cache that and then deny
        # access to `POST /wips` (or `GET /wip/{wip_id+}`)
        #
        # So we need to convert
        # `arn:aws:execute-api:us-1:abc:123/dev/GET/v1/wips` to `arn:aws:execute-api:us-1:abc:123/prod/*/v1/*`
        resource_parts = method_arn.to_s.split(%r{[A-Z]+\/})
        "#{resource_parts.first}*"
      end

      # Establish a connection to the RDS DB
      def _establish_connection
        # Fetch the DB credentials from SSM parameter store
        username = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_username)
        password = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_password)
        Uc3DmpRds::Adapter.connect(username: username, password: password)
      end
    end
  end
end
