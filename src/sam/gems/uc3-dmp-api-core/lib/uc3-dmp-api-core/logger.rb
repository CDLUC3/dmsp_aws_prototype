# frozen_string_literal: true

require_relative './notifier'

module Uc3DmpApiCore
  # Standardized ways for logging messages and errors to CloudWatch
  #
  # Methods expect the following inputs:
  #   - source:       the name of the Lambda function or Layer file
  #   - message:      the error message as a String or Array of Strings
  #   - details:      any additional context as a Hash
  #   - event:        the Lambda event if available
  #
  # --------------------------------------------------------------------------------
  class Logger
    class << self
      # rubocop:disable Metrics/AbcSize
      def log_error(source:, message:, details: {}, event: {})
        return false if source.nil? || message.nil?

        message = message.join(', ') if message.is_a?(Array)
        # Is there a better way here than just 'print'? This ends up in the CloudWatch logs
        puts "ERROR: #{source} - #{message}"
        puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
        puts " - EVENT: #{event.to_json}" if event.is_a?(Hash) && event.keys.any?

        Notifier.notify_administrator(source: source, details: details, event: event)
      end
      # rubocop:enable Metrics/AbcSize

      def log_message(source:, message:, details: {}, event: {})
        return false if source.nil? || message.nil?

        message = message.join(', ') if message.is_a?(Array)

        # Is there a better way here than just 'print'? This ends up in the CloudWatch logs
        puts "INFO: #{source} - #{message}"
        puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
        true
      end
    end
  end
end
