# frozen_string_literal: true

require 'aws-sdk-dynamodb'

# Recursive function that goes and fetches every unique PK from the Dynamo table
def fetch_records(client:, table:, item_type:, source:, items: [], last_key: '')
  args = {
    table_name: table,
    consistent_read: false,
    key_conditions: {
      PK: {
        attribute_value_list: [item_type],
        comparison_operator: 'EQ'
      }
    },
    filter_expression: '#source = :source',
    expression_attribute_names: { '#source': '_SOURCE' },
    expression_attribute_values: { ':source': source&.upcase },
    projection_expression: 'SK'
  }
  args[:exclusive_start_key] = last_key unless last_key == ''
  resp = client.query(args)

  # p "Scanning - Item Count: #{resp.count}, Last Key: #{resp.last_evaluated_key}"
  items += resp.items
  return fetch_records(client:, table:, item_type:, source:, items:, last_key: resp.last_evaluated_key) unless resp.last_evaluated_key.nil?

  items
end

if ARGV.length >= 4
  env = ARGV[0]
  item_type = ARGV[1]
  source = ARGV[2]
  table = ARGV[3]

  client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # Fetch all of the DMP ID records
  items = fetch_records(client: client, table: table, item_type:, source:)
  puts "Found #{items.length} unique DMP-IDs. Updating the index ...."
  cntr = 0
  items.each do |item|
    puts "Removing #{item['SK']}"
    client.delete_item({
      table_name: table,
      key: { PK: item_type, SK: item['SK'] }
    })
  end
else
  puts "Expected 4 arguments, the environment, the typeahead item type (aka: PK) and the DynamoTable name!"
  puts "    (e.g. `ruby clear_typeahead_for_source.rb dev INSTITUTION ROR uc3-dmp-hub-dev-regional-dynamo-TypeaheadTable-123`)"
end
