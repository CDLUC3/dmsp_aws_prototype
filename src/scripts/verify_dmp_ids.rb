require 'csv'
require 'httparty'

DOI_REGEX = %r{[0-9]{2}\.[0-9]{4,}/[a-zA-Z0-9/_.-]+}

if ARGV.length >= 2
  @env = ARGV[0] || 'dev'
  @file_name = ARGV[1]

  puts "Checking each DMP-ID in the CSV file to determine if it exists in the DMPHub and EZID."
  puts "This script will only report when a DMP-ID does not appear in one of those systems"
  puts "..."

  File.open(@file_name) do |file|
    counter = 1
    CSV.foreach(file) do |row|
      dmp_id = row[0].match(DOI_REGEX).to_s
      puts "Expected a DMP ID in row #{counter}, column 1 but found \"#{row[0]}\" instead." if dmp_id.nil? || dmp_id == ''
      next if dmp_id.nil? || dmp_id == ''

      counter += 1

      # Then check to see if the DMPHub knows about it
      opts = { headers: { Accept: 'application/json' }, follow_redirects: true, limit: 3 }
      resp = HTTParty.get("https://api.dmphub.uc3#{@env}.cdlib.net/dmps/#{dmp_id}", opts)
      json = JSON.parse(resp.body)
      in_dmphub = resp.code == 200 && json.fetch('items', []).any?

      # Finally check to see if EZID knows about it
      ezid_host = @env == 'prd' ? 'ezid.cdlib.org' : 'ezid-stg.cdlib.org'
      resp = HTTParty.get("https://#{ezid_host}/id/doi:#{dmp_id}", opts)
      in_ezid = resp.code == 200

      puts "MISSING DMP-ID: '#{dmp_id}' -- in DMPHub? #{in_dmphub} -- in EZID? #{in_ezid}" unless in_dmphub && in_ezid
    rescue StandardError => e
      puts "ERROR: #{e.message}"
      next
    end
  end
else
  puts 'Expected the env and a CSV file name (located in this dir). For example `ruby verify_dmp_ids.rb dev dmps.csv'
end
