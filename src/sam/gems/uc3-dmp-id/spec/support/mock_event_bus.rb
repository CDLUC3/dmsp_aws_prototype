# frozen_string_literal: true

module Uc3DmpEventBridge
  # Mock replacement of the EventBridge so we can check message structures
  class Publisher
    attr_accessor :event_bus

    def initialize(**_args)
      @event_bus = []
    end

    # rubocop:disable Lint/UnusedMethodArgument
    def publish(source:, dmp:, event_type: DEFAULT_EVENT_TYPE, detail: nil, logger: nil)
      @event_bus << {
        time: Time.now.utc,
        source: "#{ENV.fetch('DOMAIN', nil)}:lambda:event_publisher",
        detail_type: event_type.to_s,
        detail: detail,
        event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil)
      }
    end
    # rubocop:enable Lint/UnusedMethodArgument
  end
end
