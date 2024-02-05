# frozen_string_literal: true

require 'httparty'
require 'json'
require 'uri'

module Uc3DmpExternalApi
  # Error from the External API
  class ExternalApiError < StandardError; end

  # Helper class for communicating with external APIs
  class Client
    MSG_ERROR_FROM_EXTERNAL_API = 'Received an error from %<url>s'
    MSG_HTTPARTY_ERR = 'HTTParty failure when trying to call %<url>s'
    MSG_INVALID_URI = '%<url>s is an invalid URI'
    MSG_UNABLE_TO_PARSE = 'Unable to parse the response from %<url>s'

    class << self
      # Call the specified URL using the specified HTTP method, body and headers
      # rubocop:disable Metrics/AbcSize, Metrics/ParameterLists
      def call(url:, method: :get, body: '', basic_auth: {}, additional_headers: {}, logger: nil)
        uri = URI(url)
        # Skip the body if we are doing a get
        body = nil if method.to_sym == :get
        opts = _options(body:, basic_auth:, additional_headers:, logger:)
        resp = HTTParty.send(method.to_sym, uri, opts)

        unless [200, 201].include?(resp.code)
          msg = "status: #{resp&.code}, body: #{resp&.body}"
          raise ExternalApiError, "#{format(MSG_ERROR_FROM_EXTERNAL_API, url:)} - #{msg}"
        end
        resp.body.nil? || resp.body.empty? ? nil : _process_response(resp:)
      rescue JSON::ParserError
        raise ExternalApiError, format(MSG_UNABLE_TO_PARSE, url:)
      rescue HTTParty::Error => e
        raise ExternalApiError, "#{format(MSG_HTTPARTY_ERR, url:)} - #{e.message}"
      rescue HTTParty::ResponseError => e
        raise ExternalApiError, "#{format(MSG_HTTPARTY_ERR, url:)} - #{e.message}"
      rescue URI::InvalidURIError
        raise ExternalApiError, format(MSG_INVALID_URI, url:)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/ParameterLists

      private

      # # Handle the response body based on the Content-Type
      def _process_response(resp:)
        return nil if resp.body.nil? || resp.body.empty?
        return resp.body.to_s unless resp.headers.fetch('content-type', '').include?('application/json')

        JSON.parse(resp.body)
      end

      # Prepare the headers
      def _headers(additional_headers: {})
        domain = ENV['DOMAIN'].nil? ? 'dmptool.org' : ENV['DOMAIN']
        email = ENV['ADMIN_EMAIL'].nil? ? 'dmptool@ucop.edu' : ENV['ADMIN_EMAIL']
        base = {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'User-Agent': "California Digital Library - #{domain} (mailto:#{email})"
        }
        base.merge(additional_headers)
      end

      # Prepare the HTTParty gem options
      def _options(body:, basic_auth: nil, additional_headers: {}, logger: nil)
        hdrs = _headers(additional_headers:)
        opts = {
          headers: hdrs,
          follow_redirects: true,
          limit: 6
        }
        opts[:basic_auth] = basic_auth if basic_auth.is_a?(Hash) && basic_auth.keys.any?
        # If the body is not already JSON and we intend to send JSON, convert it
        opts[:body] = body.is_a?(Hash) && hdrs['Content-Type'] == 'application/json' ? body.to_json : body
        # If debug is enabled then tap into the HTTParty gem's debug option
        opts[:debug_output] = $stdout if logger&.level == 'debug'
        opts
      end
    end
  end
end
