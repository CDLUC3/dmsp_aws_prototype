# frozen_string_literal: true

require 'aws-sdk-sns'

require 'json'

# --------------------------------------------------------------------------------
# Responder
#
# Shared helper methods for Lambdas that facilitate logging errors and generating
# standardized JSON responses
# --------------------------------------------------------------------------------
class Responder
  DEFAULT_PAGE = 1
  DEFAULT_PER_PAGE = 25
  MAXIMUM_PER_PAGE = 250
  DEFAULT_STATUS_CODE = 500

  TIMESTAMP_FORMAT = '%Y-%m-%dT%H:%M:%S%L%Z'

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
      url = _url_from_event(event: args[:event]) || SsmReader.get_ssm_value(key: SsmReader::API_BASE_URL)
      return { statusCode: DEFAULT_STATUS_CODE, body: { errors: ["#{Messages::MSG_INVALID_ARGS} - resp"] } } if url.nil?

      errors = [errors] unless errors.nil? || errors.is_a?(Array)
      item_count = items.is_a?(Array) ? items.length : 0
      page = args[:page] || DEFAULT_PAGE
      per_page = args[:per_page] || DEFAULT_PER_PAGE

      body = {
        status: status.to_i,
        requested: url,
        requested_at: Time.now.strftime(TIMESTAMP_FORMAT),
        total_items: item_count,
        items: items.is_a?(Array) ? items.map { |dmp| _cleanse_dmp_json(json: dmp) }.compact : []
      }

      body[:errors] = errors if errors.is_a?(Array) && errors.any?
      body = _paginate(url: url, item_count: item_count, body: body, page: page, per_page: per_page)

      # If this is a server error, then notify the administrator!
      log_error(source: url, message: errors, details: body, event: args[:event]) if status == 500

      { statusCode: status.to_i, body: body.to_json }
    rescue StandardError => e
      puts "LambdaLayer: Responder.respond - #{e.message}"
      puts " - STACK: #{e.backtrace}"
      { statusCode: DEFAULT_STATUS_CODE, body: { errors: ["#{Messages::MSG_INVALID_ARGS} - resp err"] } }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Standardized way for logging fatal errors to CloudWatch
    #
    # Expects the following inputs:
    #   - source:       the name of the Lambda function or Layer file
    #   - message:      the error message as a String or Array of Strings
    #   - details:      any additional context as a Hash
    #   - event:        the Lambda event if available
    #
    # --------------------------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def log_error(source:, message:, details: {}, event: {})
      return false if source.nil? || message.nil?

      message = message.join(', ') if message.is_a?(Array)

      # Is there a better way here than just 'print'? This ends up in the CloudWatch logs
      puts "ERROR: #{source} - #{message}"
      puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
      puts " - EVENT: #{event.to_json}" if event.is_a?(Hash) && event.keys.any?

      !_notify_administrator(source: source, details: details, event: event).nil?
    end
    # rubocop:enable Metrics/AbcSize

    def log_message(source:, message:, details: {})
      return false if source.nil? || message.nil?

      message = message.join(', ') if message.is_a?(Array)

      # Is there a better way here than just 'print'? This ends up in the CloudWatch logs
      puts "INFO: #{source} - #{message}"
      puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
      true
    end
    # --------------------------------------------------------------------------------
    # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS MODULE
    # --------------------------------------------------------------------------------

    # Figure out the requested URL from the Lambda event hash
    # --------------------------------------------------------------------------------
    def _url_from_event(event:)
      return '' unless event.is_a?(Hash)

      url = event.fetch('path', '/')
      return url if event['queryStringParameters'].nil?

      "#{url}?#{event['queryStringParameters'].map { |k, v| "#{k}=#{v}" }.join('&')}"
    end

    # Sends the Administrator an email notification
    # --------------------------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def _notify_administrator(source:, details:, event: {})
      payload = "DMPHub has encountered a fatal error while processing a Lambda request.\n\n /
        SOURCE: #{source}\n
        TIME STAMP: #{Time.now.strftime('%Y-%m-%dT%H:%M:%S%L%Z')}\n
        NOTES: Check the CloudWatch logs for additional details.\n\n"
      payload += "CALLER RECEIVED: #{event.to_json}\n\n" if event.is_a?(Hash) && event.keys.any?
      payload += "DETAILS: #{details.to_json}\n\n" if details.is_a?(Hash) && details.keys.any?
      payload += "This is an automated email generated by the ResponderFunction lambda. /
                  Please do not reply to this message."

      Aws::SNS::Client.new.publish(
        topic_arn: ENV.fetch('SNS_FATAL_ERROR_TOPIC', nil),
        subject: "DMPHub - fatal error in - #{source}",
        message: payload
      )
      "Message sent: #{payload}"
    rescue Aws::Errors::ServiceError => e
      puts "UNABLE TO NOTIFY ADMINISTRATOR! - #{e.message} - on #{source}"
      puts " - EVENT: #{event.to_json}" if event.is_a?(Hash) && event.keys.any?
      puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
      nil
    end
    # rubocop:enable Metrics/AbcSize

    # Add pagination linkss to the :body
    # rubocop:disable Metrics/AbcSize
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # --------------------------------------------------------------------------------
    def _paginate(url:, item_count:, body:, page: DEFAULT_PAGE, per_page: DEFAULT_PER_PAGE)
      return body if url.nil? || item_count.nil? || !body.is_a?(Hash)

      page = DEFAULT_PAGE unless page.is_a?(Integer)
      per_page = DEFAULT_PER_PAGE unless per_page.is_a?(Integer)
      total_pages = _page_count(total: item_count, per_page: per_page)

      first_link = _pagination_link(url: url, target_page: 1, per_page: per_page)
      prev_link = _pagination_link(url: url, target_page: page - 1, per_page: per_page)
      next_link = _pagination_link(url: url, target_page: page + 1, per_page: per_page)
      last_link = _pagination_link(url: url, target_page: total_pages, per_page: per_page)

      page = total_pages if page > total_pages

      body[:page] = page
      body[:per_page] = per_page

      body[:first] = first_link unless page == 1
      body[:prev] = prev_link unless page == 1
      body[:next] = next_link unless page == total_pages
      body[:last] = last_link unless page == total_pages
      body
    end
    # rubocop:enable Metrics/AbcSize
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Generate a pagination link
    # --------------------------------------------------------------------------------
    def _pagination_link(url:, target_page:, per_page: DEFAULT_PER_PAGE)
      return nil if url.nil? || target_page.nil?

      link = _url_without_pagination(url: url)
      return nil if link.nil?

      link += '?' unless link.include?('?')
      link += '&' unless link.end_with?('&') || link.end_with?('?')
      "#{link}page=#{target_page}&per_page=#{per_page}"
    end

    # Determine the total number of pages
    # --------------------------------------------------------------------------------
    def _page_count(total:, per_page: DEFAULT_PER_PAGE)
      return 1 if total.nil? || per_page.nil? || !total.positive? || !per_page.positive?

      (total.to_f / per_page).ceil
    end

    # Remove the pagination query parameters from the URL
    # --------------------------------------------------------------------------------
    def _url_without_pagination(url:)
      return nil if url.nil? || !url.is_a?(String)

      parts = url.split('?')
      out = parts.first
      query_args = parts.length <= 1 ? [] : parts.last.split('&')
      query_args = query_args.reject { |arg| arg.start_with?('page=') || arg.start_with?('per_page=') }
      return out unless query_args.any?

      "#{out}?#{query_args.join('&')}"
    end

    # Recursive method that strips out any DMPHub related metadata from a DMP record before sending
    # it to the caller
    # --------------------------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def _cleanse_dmp_json(json:)
      return json unless json.is_a?(Hash) || json.is_a?(Array)

      # If it's an array clean each of the objects individually
      return json.map { |obj| _cleanse_dmp_json(json: obj) }.compact if json.is_a?(Array)

      cleansed = {}
      json.each_key do |key|
        next if key.to_s.start_with?('dmphub') || %w[PK SK].include?(key.to_s)

        obj = json[key]
        # If this object is a Hash or Array then recursively cleanse it
        cleansed[key] = obj.is_a?(Hash) || obj.is_a?(Array) ? _cleanse_dmp_json(json: obj) : obj
      end
      cleansed.keys.any? ? cleansed : nil
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  end
end
