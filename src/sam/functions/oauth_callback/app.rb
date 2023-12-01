# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'httparty'
require 'base64'
require 'json'
require 'uri'

require 'aws-sdk-ssm'

module Functions
  # The handler for GET /oauth_callback?code=[Oauth2GrantCode]
  class OauthCallback
    SOURCE = 'GET /oauth_callback'

    def self.process(event:, context:)
      puts event['queryStringParameters']

      opts = _options(code: event.fetch('queryStringParameters', {})['code'])
      resp = HTTParty.send(:post, ENV['AUTH_ENDPOINT'], opts)
      return { statusCode: 500, body: "Unable to acquire token" } if resp.body.nil? || resp.body.empty?

      { statusCode: 200, body: resp.body.to_json, headers: _response_headers }
    end

    private

    # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
    def self._get_ssm_val(key:)
      resp = Aws::SSM::Client.new.get_parameter(name: key, with_decryption: true)
      resp&.parameter&.value
    end

    # Setup the Options that will be sent to Cognito to exchange the Auth Code for a Token
    def self._options(code:)
      callback_uri = ENV['CALLBACK_ENDPOINT']
      client_id = _get_ssm_val(key: "#{ENV['SSM_PATH']}DmspClientId")
      client_secret = _get_ssm_val(key: "#{ENV['SSM_PATH']}DmspClientSecret")

      ret = {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': "Basic #{Base64.encode64("#{client_id}:#{client_secret}").gsub(/\n/, '')}",
          'User-Agent': "Cognito auth tester"
        },
        body: "grant_type=authorization_code&code=#{code}&redirect_uri=#{callback_uri}&client_id=#{client_id}",
        follow_redirects: true,
        limit: 6
      }
      ret[:debug_output] = $stdout if ENV['LOG_LEVEL'] == 'debug'
      ret
    end

    # Assign CORS headers to the response
    def self._response_headers
      { 'access-control-allow-origin': ENV.fetch('CORS_ORIGIN', nil) }
    end
  end
end
