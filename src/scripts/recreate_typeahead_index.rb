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
    filter_expression: '_SOURCE = :source',
    expression_attribute_values: { ':source': source&.upcase }
    projection_expression: 'SK'
  }
  args[:exclusive_start_key] = last_key unless last_key == ''
  resp = client.query(args)

  # p "Scanning - Item Count: #{resp.count}, Last Key: #{resp.last_evaluated_key}"
  items += resp.items
  return fetch_records(client:, table:, item_type:, source:, items:, last_key: resp.last_evaluated_key) unless resp.last_evaluated_key.nil?

  items
end

if ARGV.length >= 3
  env = ARGV[0]
  item_type = ARGV[1]
  table = ARGV[2]

  dynamo = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # Fetch all of the DMP ID records
  items = fetch_records(client: client, table: table, item_type:, source:)
  puts "Found #{items.length} unique DMP-IDs. Updating the index ...."
  cntr = 0
  items.each do |item|
    # Fetch the full record
    resp = dynamo.get_item({
      table_name: table,
      key: {  PK: item_type, SK: item['SK'] },
      consistent_read: false
    })
    hash = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
    puts "Couldn't load the full record for #{item}!" if hash.nil?
    next if hash.nil?

    # Update an internal field that will trigger the dynamo stream update without altering any of the
    # true DMP-ID fields
    hash['dmphub_forced_index_recreation_date'] = Time.now.strftime('%Y-%m-%dT%H:%M')
    dynamo.put_item({
      table_name: table,
      item: hash
    })
    cntr += 1
  end

  puts "Done. Updated the index for #{cntr} DMP-IDs."
else
  puts "Expected 3 arguments, the environment, item type (e.g. INSTITUTION) and the DynamoTable name!"
end
