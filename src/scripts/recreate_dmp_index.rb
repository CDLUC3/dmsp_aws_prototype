# frozen_string_literal: true

require 'aws-sdk-dynamodb'

# Recursive function that goes and fetches every unique PK from the Dynamo table
def fetch_dmp_ids(client:, table:, items: [], last_key: '')
  args = {
    table_name: table,
    consistent_read: false,
    projection_expression: 'PK',
    expression_attribute_values: { ':version': 'VERSION#latest' },
    filter_expression: 'SK = :version'
  }
  args[:exclusive_start_key] = last_key unless last_key == ''
  resp = client.scan(args)

  # p "Scanning - Item Count: #{resp.count}, Last Key: #{resp.last_evaluated_key}"
  items += resp.items
  return fetch_dmp_ids(client:, table:, items:, last_key: resp.last_evaluated_key) unless resp.last_evaluated_key.nil?

  items
end

if ARGV.length >= 2
  env = ARGV[0]
  table = ARGV[1]

  dynamo = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # Fetch all of the DMP ID records
  items = fetch_dmp_ids(client: dynamo, table: table)
  puts "Found #{items.length} unique DMP-IDs. Updating the index ...."
  cntr = 0
  items.each do |item|
    # Fetch the full record
    resp = dynamo.get_item({
      table_name: table,
      key: {  PK: item['PK'], SK: 'VERSION#latest' },
      consistent_read: false
    })
    dmp = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
    puts "Couldn't load the full record for #{item}!" if dmp.nil?
    next if dmp.nil?

    # Update an internal field that will trigger the dynamo stream update without altering any of the
    # true DMP-ID fields
    dmp['dmphub_forced_index_recreation_date'] = Time.now.strftime('%Y-%m-%dT%H:%M')
    dynamo.put_item({
      table_name: table,
      item: dmp
    })
    cntr += 1
  end

  puts "Done. Updated the index for #{cntr} DMP-IDs."
else
  puts "Expected 2 arguments, the environment and the DynamoTable name!"
end
