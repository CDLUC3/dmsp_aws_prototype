# frozen_string_literal: true

module Uc3DmpEventBridge
  class PublisherError < StandardError; end

  # CLass to manage publication of messages on an EventBridge's EventBus
  class Publisher
    SOURCE = 'Uc3DmpEventBridge::Publisher'

    DEFAULT_EVENT_TYPE = 'DMP change'

    MSG_BUS_ERROR = 'EventBus Error - %{msg} - %{trace}'
    MSG_INVALID_KEY = 'Invalid message specified. Expecting Hash containing at least a `PK` and `SK`'
    MSG_MISSING_BUS = 'No EventBus defined! Looking for `ENV[\'EVENT_BUS_NAME\']`'
    MSG_MISSING_DOMAIN = 'No domain name defined! Looking for `ENV[\'DOMAIN\']`'

    attr_accessor :client, :bus, :domain

    def initialize(**_args)
      @bus = ENV.fetch('EVENT_BUS_NAME', nil)
      @domain = ENV.fetch('DOMAIN', nil)
      raise PublisherError, MSG_MISSING_BUS if @bus.nil?
      raise PublisherError, MSG_MISSING_DOMAIN if @domain.nil?

      @client = Aws::EventBridge::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
    end

    # Publish an event to the EventBus so that other Lambdas can do their thing
    # rubocop:disable Metrics/AbcSize
    def publish(source:, dmp:, event_type: DEFAULT_EVENT_TYPE, logger: nil)
      source = "#{source} -> #{SOURCE}.publish"

      message = {
        entries: [{
          time: Time.now,
          source: "#{ENV.fetch('DOMAIN', nil)}:lambda:event_publisher",
          detail_type: event_type.to_s,
          detail: _generate_detail(dmp: dmp).to_json,
          event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil)
        }]
      }
      logger.debug(message: "#{SOURCE} published event", details: message) if logger.respond_to?(:debug)
      resp = client.put_events(message)
      return true unless resp.failed_entry_count.nil? || resp.failed_entry_count.positive?

      # The EventBridge returned errors, so log the error
      raise PublisherError, _generate_failure(source: source, response: resp, payload: payload)
    rescue Aws::Errors::ServiceError => e
      logger.error(message: "#{SOURCE} #{e.message}", details: e.backtrace) if logger.respond_to?(:debug)
      raise PublisherError, MSG_BUS_ERROR % { msg: e.message }
    end
    # rubocop:enable Metrics/AbcSize

    private

    # Only post the bits of the DMP that are required for the message to cut down on size
    def _generate_detail(dmp:)
      {
        PK: dmp['PK'],
        SK: dmp['SK'],
        dmphub_provenance_id: dmp.fetch('dmphub_provenance_id', nil),
        dmproadmap_links: dmp.fetch('dmproadmap_links', {}),
        dmphub_updater_is_provenance: dmp.fetch('dmphub_updater_is_provenance', false)
      }
    end

    # If the EventBus returns an error log everything
    def _generate_failure(source:, response:, payload:)
      {
        source: source,
        message: 'Failed to post message to EventBridge!',
        details: {
          event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil),
          event_id: response.data.entries[0].event_id,
          error_code: response.data.entries[0].error_code,
          error_message: response.data.entries[0].error_message,
          detail: payload
        }
      }
    end
  end
end
