# frozen_string_literal: true

require 'aws-sdk-eventbridge'

require 'json'

# --------------------------------------------------------------------------------
# Responder
#
# Shared helper methods for Lambdas that facilitate logging errors and generating
# standardized JSON responses
# --------------------------------------------------------------------------------
class EventPublisher
  DEFAULT_EVENT_TYPE = 'DMP change'

  class << self
    # Publish an event to the EventBus so that other Lambdas can do their thing
    # rubocop:disable Metrics/AbcSize
    def publish(source:, dmp:, event_type: DEFAULT_EVENT_TYPE, debug: false)
      source = "#{source} -> EventPublisher.publish"
      return false if ENV['EVENT_BUS_NAME'].nil? || dmp.nil?

      client = Aws::EventBridge::Client.new(region: ENV.fetch('AWS_REGION', nil))
      message = {
        entries: [{
          time: Time.now,
          source: "#{ENV.fetch('DOMAIN', nil)}:lambda:event_publisher",
          detail_type: event_type.to_s,
          detail: generate_detail(dmp: dmp).to_json,
          event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil)
        }]
      }
      Responder.log_message(source: source, message: 'Publishing event', details: message) if debug
      resp = client.put_events(message)
      return true unless resp.failed_entry_count.nil? || resp.failed_entry_count.positive?

      # The EventBridge returned errors, so log the error
      handle_failure(source: source, response: resp, payload: payload)
      false
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: source, message: e.message, details: dmp)
      false
    end
    # rubocop:enable Metrics/AbcSize

    private

    # Only post the bits of the DMP that are required for the message to cut down on size
    def generate_detail(dmp:)
      {
        PK: dmp['PK'],
        SK: KeyHelper::DMP_LATEST_VERSION,
        dmphub_provenance_id: dmp.fetch('dmphub_provenance_id', nil),
        dmproadmap_links: dmp.fetch('dmproadmap_links', {}),
        dmphub_updater_is_provenance: dmp.fetch('dmphub_updater_is_provenance', false)
      }
    end

    # If the EventBus returns an error log everything
    def handle_failure(source:, response:, payload:)
      Responder.log_error(
        source: source,
        message: 'Failed to post message to EventBridge!',
        details: {
          event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil),
          event_id: response.data.entries[0].event_id,
          error_code: response.data.entries[0].error_code,
          error_message: response.data.entries[0].error_message,
          detail: payload
        }
      )
    end
  end
end
