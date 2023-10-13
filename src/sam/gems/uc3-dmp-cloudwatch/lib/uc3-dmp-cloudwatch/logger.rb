# frozen_string_literal: true

module Uc3DmpCloudwatch
  class LoggerError < StandardError; end

  # Helper functions for working with Dynamo JSON
  class Logger
    attr_accessor :source, :event, :request_id, :level

    LOG_LEVELS = %w[none error info debug]

    def initialize(**args)
      @level = args.fetch(:level, 'info')&.to_s&.downcase
      @level = 'info' unless LOG_LEVELS.include?(@level)

      @source = args[:source]
      @event = args[:event]
      @request_id = args[:request_id]
    end

    def error(message:, details: {})
      return false if @level == 'none' || message.nil?

      _format_msg(mode: 'error', msg: message)
      _format_msg(mode: 'error', msg: details) if _valid_details(details:)
      _log_event(mode: 'error')
    end

    def info(message:, details: {})
      return false if %w[none error].include?(@level) || message.nil?

      _format_msg(mode: 'info', msg: message)
      _format_msg(mode: 'info', msg: details) if _valid_details(details:)
    end

    def debug(message:, details: {})
      return false if %w[none error info].include?(@level) || message.nil?

      _format_msg(mode: 'debug', msg: message)
      _format_msg(mode: 'debug', msg: details) if _valid_details(details:)
    end

    private

    def _valid_details(details: nil)
      return false if details.nil?
      return false if details.is_a?(Hash) && details.keys.empty?
      return false if details.is_a?(Array) && details.empty?

      details.to_s.strip != ''
    end

    # Format the start of the message with a prefix and the AWS request id if available
    def _prefix(prefix: 'INFO')
      prefix = @request_id.nil? ? "#{prefix} " : "#{prefix} RequestId: #{@request_id},"
      prefix += " SOURCE: #{@source}," unless @source.nil?
      prefix
    end

    # Format the message
    def _format_msg(msg:, mode: 'info')
      message = msg.is_a?(Array) ? msg.join(', ') : msg
      puts "#{_prefix(prefix: mode.upcase)} #{message.is_a?(String) ? "MESSAGE: #{message}" : "PAYLOAD: #{message}"}"
    end

    # Write the event Hash
    def _log_event(mode: 'info')
      puts "#{_prefix(prefix: mode)} Event: #{@event}"
    end
  end
end
