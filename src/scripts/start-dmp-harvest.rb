require 'aws-sdk-eventbridge'

if ARGV.length >= 2
  env = ARGV[0]
  bus_arn = ARGV[1]
  client = Aws::EventBridge::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  message = {
    entries: [{
      time: Time.now.utc.iso8601,
      source: "dmphub.uc3#{env}.cdlib.net:lambda:event_publisher",
      detail_type: "ScheduleHarvest",
      detail: '{}',
      event_bus_name: bus_arn
    }]
  }

  puts "Sending a message to the EventBus to kick off the DmpHarvestable function"
  pp message

  resp = client.put_events(message)

  if resp.failed_entry_count.nil? || resp.failed_entry_count.positive?
    puts "Unable to publish message to the EventBus!"
    pp resp
  else
    puts "Done. Kicked off the HavestableDmps Lambda Function."
  end
else
  puts "Expected 2 arguments, the environment and the EventBus ARN!"
end
