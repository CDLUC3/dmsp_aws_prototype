require 'aws-sdk-dynamodb'

if ARGV.length == 1
  TABLE = ARGV[0]
  PKS = [
    'DMP#doi.org/10.48321/D10B3E54E4',
    'DMP#doi.org/10.48321/D114471AC3',
    'DMP#doi.org/10.48321/D139D84658',
    'DMP#doi.org/10.48321/D14406894e',
    'DMP#doi.org/10.48321/D145457051',
    'DMP#doi.org/10.48321/D14F38aa13',
    'DMP#doi.org/10.48321/D18F9B93B8',
    'DMP#doi.org/10.48321/D1944C8215',
    'DMP#doi.org/10.48321/D1A04A9B1D',
    'DMP#doi.org/10.48321/D1A90CCC2B',
    'DMP#doi.org/10.48321/D1BA48FBC9',
    'DMP#doi.org/10.48321/D1BAD5B94D',
    'DMP#doi.org/10.48321/D1CE350633',
    'DMP#doi.org/10.48321/D1DF9DDDAF',
    'DMP#doi.org/10.48321/D1FCB77AF0',
    'DMP#doi.org/10.48321/D1FFBFF8FE',
    'DMP#doi.org/10.48321/D1FFE5D7FD'
  ]

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

  dynamo = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # pks = PKS
  pks = fetch_dmp_ids(client: dynamo, table: TABLE)&.map { |hash| hash['PK'] }

  pks.each do |pk|

    # Fetch the full record
    resp = dynamo.get_item({
      table_name: TABLE,
      key: {  PK: pk, SK: 'VERSION#latest' },
      consistent_read: false
    })
    dmp = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
    puts "Couldn't load the full record for #{item}!" if dmp.nil?

    unless dmp.nil?
      # Update an internal field that will trigger the dynamo stream update without altering any of the
      # true DMP-ID fields
      contact_affil = dmp['contact'].fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
      contact_affil = contact_affil&.gsub('https://ror.org/https://ror.org/', 'https://ror.org/') unless contact_affil.nil?
      dmp['contact']['dmproadmap_affiliation']['affiliation_id']['identifier'] = contact_affil unless contact_affil.nil?

      dmp.fetch('contributor', []).each do |contrib|
        c_affil = contrib.fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
        c_affil = contact_affil&.gsub('https://ror.org/https://ror.org/', 'https://ror.org/') unless c_affil.nil?
        contrib['dmproadmap_affiliation']['affiliation_id']['identifier'] = contact_affil unless c_affil.nil?
      end
      dmp['dmphub_forced_index_recreation_date'] = Time.now.strftime('%Y-%m-%dT%H:%M')

      dynamo.put_item({
        table_name: TABLE,
        item: dmp
      })
      puts "Done. Index updated for #{pk}. See cloudwatch log for details"
    end
  end
else
  p "Expected 1 argument, the Dynamo table name"
end
