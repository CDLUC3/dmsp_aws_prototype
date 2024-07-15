require 'aws-sdk-dynamodb'
require 'aws-sdk-eventbridge'

# Recursive function that goes and fetches every unique PK from the Dynamo table
def fetch_dmp_ids(client:, table:, items: [], last_key: '')
  args = {
    table_name: table,
    consistent_read: false,
    projection_expression: 'PK',
    expression_attribute_values: { ':sk': 'HARVESTER_MODS' },
    filter_expression: 'SK = :sk'
  }
  args[:exclusive_start_key] = last_key unless last_key == ''
  resp = client.scan(args)

  # p "Scanning - Item Count: #{resp.count}, Last Key: #{resp.last_evaluated_key}"
  items += resp.items
  return fetch_dmp_ids(client:, table:, items:, last_key: resp.last_evaluated_key) unless resp.last_evaluated_key.nil?

  items
end

if ARGV.length >= 3
  env = ARGV[0]
  table = ARGV[1]
  bus_arn = ARGV[2]

  client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
  fetch_dmp_ids(client:, table:).each do |rec|
    # next unless rec['PK'] == 'DMP#doi.org/10.48321/D1EC399146'
    puts "DELETING #{rec}"
    resp = client.delete_item({
      key: { PK: rec['PK'], SK: 'HARVESTER_MODS' },
      table_name: table
    })
  end

  bridge = Aws::EventBridge::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
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

  resp = bridge.put_events(message)

  puts "Done."
else
  puts "Expected 3 arguments, the environment, the DynamoTable name, and EventBus ARN!"
end