require 'uc3-dmp-id'
require 'uc3-dmp-dynamo'

if ARGV.length == 2
  ENV['DYNAMO_TABLE'] = ARGV[0]
  PK = "DMP#doi.org/#{ARGV[1]}"

  p "Fetching Dynamo entry for PK: #{PK}"
  resp = Uc3DmpId::Finder.by_pk(p_key: PK, cleanse: false)
  pp resp
else
  p "Expected 2 arguments, the Dynamo table name and the DMP ID (just the shoulder and id)"
end