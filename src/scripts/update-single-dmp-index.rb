require 'aws-sdk-dynamodb'

if ARGV.length == 2
  TABLE = ARGV[0]
  PK = "DMP#doi.org/#{ARGV[1]}"

  dynamo = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # Fetch the full record
  resp = dynamo.get_item({
    table_name: TABLE,
    key: {  PK: PK, SK: 'VERSION#latest' },
    consistent_read: false
  })
  dmp = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
  puts "Couldn't load the full record for #{item}!" if dmp.nil?

  unless dmp.nil?
    # Update an internal field that will trigger the dynamo stream update without altering any of the
    # true DMP-ID fields
    dmp['dmphub_forced_index_recreation_date'] = Time.now.strftime('%Y-%m-%dT%H:%M')
    dynamo.put_item({
      table_name: TABLE,
      item: dmp
    })
    puts "Done. INdex updated. See cloudwatch log for details"
  end
else
  p "Expected 2 arguments, the Dynamo table name and the DMP ID (just the shoulder and id)"
end
