# frozen_string_literal: true

module Uc3DmpApiCore
  # Use Rails' ActiveResource to communicate with the DMPHub REST API
  class Responder
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25
    MAXIMUM_PER_PAGE = 250

    DEFAULT_STATUS_CODE = 500

    TIMESTAMP_FORMAT = '%Y-%m-%dT%H:%M:%S%L%Z'

    MSG_INVALID_ARGS = 'Invalid arguments'

    class << self
      # Standardized Lambda response
      #
      # Expects the following inputs:
      #   - status:       an HTTP status code (defaults to DEFAULT_STATUS_CODE)
      #   - items:        an array of Hashes
      #   - errors:       and array of Strings
      #   - args:         currently only allows for the Lambda :event
      #
      # Returns a hash that is a valid Lambda API response
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def respond(status: DEFAULT_STATUS_CODE, items: [], errors: [], **args)
        url = _url_from_event(event: args[:event]) || SsmReader.get_ssm_value(key: 'api_base_url')
        return _standard_error(url: url) if url.nil?

        args = JSON.parse(args.to_json)
        errors = [errors] unless errors.nil? || errors.is_a?(Array)
        item_count = items.is_a?(Array) ? items.length : 0

        body = {
          status: status.to_i,
          requested: url,
          requested_at: Time.now.strftime(TIMESTAMP_FORMAT),
          total_items: item_count,
          items: items.is_a?(Array) ? Paginator.paginate(params: args, results: items) : [],
          errors: errors
        }
        body = body.merge(Paginator.pagination_meta(url: url, item_count: item_count, params: args))

        # If this is a server error, then notify the administrator!
        log_error(source: url, message: errors, details: body, event: args[:event]) if status.to_s[0] == '5'

        { statusCode: status.to_i, body: body.compact.to_json, headers: headers }
      rescue StandardError => e
        puts "Uc3DmpApiCore.Responder.respond - #{e.message}"
        puts " - STACK: #{e.backtrace}"
        _standard_error(url: url)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Format an error response for any issues within this Responder!
      def _standard_error(url:, status: DEFAULT_STATUS_CODE, message: Uc3DmpApiCore::MSG_SERVER_ERROR)
        body = {
          status: status.to_i,
          requested: url,
          requested_at: Time.now.strftime(TIMESTAMP_FORMAT),
          total_items: 0,
          errors: [message]
        }
        { statusCode: DEFAULT_STATUS_CODE, body: body.compact.to_json, headers: headers }
      end

      # Figure out the requested URL from the Lambda event hash
      # --------------------------------------------------------------------------------
      def _url_from_event(event:)
        return '' unless event.is_a?(Hash)

        url = event.fetch('path', '/')
        return url if event['queryStringParameters'].nil?

        "#{url}?#{event['queryStringParameters'].map { |k, v| "#{k}=#{v}" }.join('&')}"
      end

      def headers
        return {} if ENV['CORS_ORIGIN'].nil?

        {
          'Access-Control-Allow-Headers': ENV['CORS_HEADERS'],
          'Access-Control-Allow-Origin': ENV['CORS_ORIGIN'],
          'Access-Control-Allow-Methods': ENV['CORS_METHODS']
        }
      end
    end
  end
end
