# frozen_string_literal: true

require 'aws-sdk-sns'

module Uc3DmpApiCore
  # Helper functions to send emails via SNS or publish events to EventBridge
  class Notifier
    class << self
      # Sends the Administrator an email notification
      # --------------------------------------------------------------------------------
      def notify_administrator(source:, details:, event: {})
        Aws::SNS::Client.new.publish(
          topic_arn: ENV.fetch('SNS_FATAL_ERROR_TOPIC', nil),
          subject: "DMPTool - fatal error in - #{source}",
          message: _build_admin_message(source: source, details: details, event: event)
        )
        true
      rescue Aws::Errors::ServiceError => e
        puts "Uc3DmpCore.Notifier - Unable to notify administrator via SNS! - #{e.message} - on #{source}"
        puts " - EVENT: #{event.to_json}" if event.is_a?(Hash) && event.keys.any?
        puts " - DETAILS: #{details.to_json}" if details.is_a?(Hash) && details.keys.any?
        false
      end

      private

      # Format the Admin email message
      def _build_admin_message(source:, details:, event: {})
        payload = "DMPTool #{ENV.fetch('LAMBDA_ENV',
                                       'dev')} has encountered a fatal error within a Lambda function.\n\n /
          SOURCE: #{source}\n /
          TIME STAMP: #{Time.now.strftime('%Y-%m-%dT%H:%M:%S%L%Z')}\n /
          NOTES: Check the CloudWatch logs for additional details.\n\n"
        payload += "CALLER RECEIVED: #{event.to_json}\n\n" if event.is_a?(Hash) && event.keys.any?
        payload += "DETAILS: #{details.to_json}\n\n" if details.is_a?(Hash) && details.keys.any?
        payload += "This is an automated email generated by the Uc3DmpCore.Notifier gem.\n /
                    Please do not reply to this message."
        payload
      end
    end
  end
end
