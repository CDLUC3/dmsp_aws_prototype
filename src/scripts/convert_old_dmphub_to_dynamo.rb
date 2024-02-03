require 'base64'
require 'httparty'

DOI_REGEX = %r{[0-9]{2}\.[0-9]{4,}/[a-zA-Z0-9/_.-]+}

DMP_IDS = [
  "https://doi.org/10.48321/D13S3Z",
  "https://doi.org/10.48321/D1C885",
  "https://doi.org/10.48321/D1G01P",
  "https://doi.org/10.48321/D1H010",
  "https://doi.org/10.48321/D1KS39",
  "https://doi.org/10.48321/D1MS3M"
]

# Recursively transform the JSON into Dynamo JSON
def json_to_dynamo_json(entry:, is_root: false)
  return { "S": "" } if entry.nil?
  # if the value is a string:
  return  { "S": entry.gsub("'", "") } if entry.is_a?(String)
  # if the value is a float:
  return { "N": "#{entry}" } if entry.is_a?(Float)
  # If it's an array process each item
  return { "L": entry.map { |entry| json_to_dynamo_json(entry: entry) } } if entry.is_a?(Array)

  out = {}
  # Process each key
  entry.keys.each do |key|
    # Fix up any key names if they do not match the current common standard
    new_key = case key
              when 'affiliation'
                'dmproadmap_affiliation'
              when 'related_identifiers'
                'dmproadmap_related_identifiers'
              else
                key
              end
    out[new_key] = json_to_dynamo_json(entry: entry["#{key}"])
  end

  is_root ? out : { "M": out }
end

env = ARGV[0]
dynamo_table = ARGV[1]
ezid_username = ARGV[2]
ezid_password = ARGV[3]

if ARGV.length < 4
  puts "Expecting 4 arguments!"
  puts "   1 - Environment (e.g. dev, stg, prd)"
  puts "   2 - Dynamo Table Name (the name not the ARN)"
  puts "   3 - EZID Username"
  puts "   4 - EZID Password"
else
  ezid_api = "https://ezid.cdlib.org"
  target_url = "https://dmphub.uc3#{env}.cdlib.net/dmps/"
  creds = Base64.encode64("#{ezid_username}:#{ezid_password}").chomp
  puts 'Missing DMPROADMAP_DMPHUB_LANDING_PAGE_URL' if target_url.nil?

  ezid_opts = {
    headers: {
      Accept: 'text/plain',
      Authorization: "Basic #{creds}",
      'Content-Type': 'text/plain',
      'User-Agent': "DMPHub uc3@ucop.edu"
    },
    follow_redirects: true
    # , debug_output: $stdout
  }

  unless creds.nil?
    DMP_IDS.each do |entry|
      dmp_id = entry.match(DOI_REGEX).to_s
      puts "WARN: Expected a DMP ID but found \"#{entry}\" instead." if dmp_id.nil? || dmp_id == ''
      next if dmp_id.nil? || dmp_id == ''

      #
      opts = { headers: { Accept: 'application/json' }, follow_redirects: true, limit: 3 }
      resp = HTTParty.get("https://api.dmphub.uc3#{env}.cdlib.net/dmps/#{dmp_id}", opts)
      puts "WARN: #{dmp_id} already exists in the new DMPHub ... updating record" if resp.code == 200 &&
                                                                  JSON.parse(resp.body).fetch('items', []).any?
      # next if resp.code == 200 && JSON.parse(resp.body).fetch('items', []).any?

      # Fetch the DMP METADATA out of the old hub
      resp = HTTParty.get("https://dmphub.cdlib.org/dmps/doi:#{dmp_id}.json", opts)
      puts "WARN: Could not find #{dmp_id} in the Old DMPhub system!" unless resp.code == 200
      next unless resp.code == 200

      json = JSON.parse(resp.body)
      dmp = json.fetch('items', []).first&.fetch('dmp', {})
      puts "WARN: DMPHub returned NO content for #{dmp_id}!" if dmp.nil? || dmp.keys.empty?
      next if dmp.nil? || dmp.keys.empty?

      dmp.delete('schema')
      dmp.delete('extensions')
      dmp.delete('dmphub_links')

      contact = dmp.fetch('contact', {})
      contact = dmp.fetch('contributor': []).first if contact.nil?
      puts "WARN: No contact could be found for #{dmp_id}" if contact.nil?
      next if contact.nil?

      dmp['PK'] = "DMP#doi.org/#{dmp_id}"
      dmp['SK'] = "VERSION#latest"
      dmp['dmphub_modification_day'] = dmp.fetch('modified', '')[0..10]
      dmp['dmphub_owner_id'] = contact.fetch('contact_id', contact.fetch('contributor_id', {}))['identifier']
      dmp['dmphub_owner_org'] = contact.fetch('dmproadmap_affiliation', {}).fetch('affiliation_id', {})['identifier']
      dmp['dmphub_owner_org'] = contact.fetch('affiliation', {}).fetch('affiliation_id', {})['identifier'] if dmp['dmphub_owner_org'].nil?
      dmp['dmphub_provenance_id'] = 'PROVENANCE#DMPHub'
      dmp['dmphub_provenance_identifier'] = entry
      dmp['dmproadmap_privacy'] = 'private'

      # If the dmp_id in the JSON doesn't match the dmp_id we are using for the PK, change it
      if !dmp.fetch('dmp_id', {})['identifier'].nil? && dmp['dmp_id']['identifier'] != "https://doi.org/#{dmp_id}"
        old_one = dmp['dmp_id']['identifier']
        dmp['dmp_id'] = JSON.parse({ type: 'doi', identifier: "https://doi.org/#{dmp_id}" }.to_json)
        dmp['related_identifiers'] = [] unless dmp['related_identifiers'].is_a?(Array)
        dmp['related_identifiers'] << JSON.parse({ type: "doi", identifier: old_one, descriptor: "is_metadata_for" }.to_json)
      end

      # Fix super old DMPs that had :project as a Hash instead of Array
      dmp['project'] = [dmp['project']] if dmp['project'].is_a?(Hash)


      # p dmp.to_json
      # p '========================='

      converted = json_to_dynamo_json(entry: dmp, is_root: true)

      # Fix any empty contributor roles
      converted.fetch('contributor', { L: [] }).fetch(:L, []).each do |contrib|
        next unless contrib[:M].fetch('role', {}).fetch(:L, []).nil? || contrib[:M]['role'].fetch(:L, []).empty?

        contrib[:M]['role'][:L] = [{ "S": "other" }]
      end

      # p converted.to_json

      if system("aws dynamodb put-item --table-name #{dynamo_table} --item '#{converted.to_json}'")
        puts "Successfully added #{dmp_id} to Dynamo. Registering it with EZID ..."

        ezid_opts[:body] = "_target: #{target_url}#{dmp_id}"
        resp = HTTParty.post("#{ezid_api}/id/doi:#{dmp_id}", ezid_opts)
        if !resp.body.nil? && !resp.body.empty? && [200, 201].include?(resp.code)
          puts 'Success'
        else
          puts 'Failure!'
        end
      else
        puts "Could not add #{dmp_id} to Dynamo!"
        pp converted
      end
      p '----------'
      p ''
    end
  end
end
