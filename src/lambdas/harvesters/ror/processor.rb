# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'digest'
require 'uri'
require 'zip'

require 'aws-sdk-s3'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-external-api'

module Functions
  # A service that fetches the latest ROR file
  class RorProcessor
    SOURCE = 'ROR Processor'

    BAD_DOWNLOAD_MSG = 'Zip archive failed the checksum validation!'
    NO_ZIP_S3_MSG = 'No Zip file found in S3!'
    UNZIP_PARSE_FAILURE_MSG = 'Unable to unzip and parse the latest ROR file!'

    ZENODO_METADATA_TARGET = 'https://zenodo.org/api/communities/ror-data/records?q=&sort=newest'
    HEADERS_HOST = 'zenodo.org'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "ExploreRor",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "zip_file": "ror/v1.5.blahblah.zip",
    #           "start_at": 0,
    #           "end_at": 50000
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        # No need to validate the source and detail-type because that is done by the EventRule
        details = event.fetch('detail', {})
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : nil
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # Download the Zip archive and extract the JSON from it
        zip_content = fetch_file_from_s3(key: details['zip_file'])
        logger&.error(message: NO_ZIP_S3_MSG, details: details) if zip_content.nil?
        return { statusCode: 500, body: NO_ZIP_S3_MSG } if zip_content.nil?

        # Connect to Dynamo
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        table = ENV.fetch('DYNAMO_TABLE')

        # Unzip and extract the JSON file
        json = unzip_and_load_json(file_name: details['zip_file'], zip_content:, logger:)
        logger&.error(message: UNZIP_PARSE_FAILURE_MSG) if json.nil?
        return { statusCode: 500, body: UNZIP_PARSE_FAILURE_MSG } if json.nil?

        # Process the ROR records in the JSON file
        rec_count = process_json(client:, table:, json:, details:, logger:)
        logger&.info(message: "Created/Updated #{rec_count} in the Dynamo Typeaheads table.")
        return { statusCode: 200, body: "Success - Created/Updated #{rec_count} entries in the Dynamo Typeaheads table" }
      rescue StandardError => e
        puts "Fatal error in RorHarvester! #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: "Fatal Server Error" }
      end

      private

      # Fetch the latest ROR zip file from S3
      def fetch_file_from_s3(key:)
        client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        bucket = ENV['S3_BUCKET'].gsub('arn:aws:s3:::', '')

        puts "Looking for #{key} in S3."
        resp = client.get_object({ bucket:, key: })
        return nil if resp.nil? || !resp.content_length.positive?

        resp.body.is_a?(String) ? resp.body : resp.body.read
      rescue StandardError => e
        puts "Failure fetching ROR zip file from S3: #{e.message}"
        puts e.backtrace
        nil
      end

      # Unzip the ROR file and extract the JSON file
      def unzip_and_load_json(file_name:, zip_content:, logger: nil)
        return nil if zip_content.nil?

        # Get the name of the file we are interested in processing
        json_file_name = file_name&.gsub('.zip', '.json')

        logger&.debug(message: "Unzipping file ROR file and looking for #{json_file_name}")
        json = ''
        Dir.mktmpdir do |tmp_dir|
          zip_file_path = File.join(tmp_dir, 'downloaded.zip')
          File.open(zip_file_path, 'wb') { |file| file.write(zip_content) }

          Zip::File.open(zip_file_path) do |files|
            files.each do |entry|
              logger.debug(message: "Searching ZipFile. Found file: #{entry&.name}")
              next if File.exist?(entry.name)

              f_path = File.join(tmp_dir, entry.name)
              FileUtils.mkdir_p(File.dirname(f_path))
              files.extract(entry, f_path) unless File.exist?(f_path)
              is_json = entry.name.downcase.include?(json_file_name.split('/').last)
              json = parse_json(json_file_path: f_path) if is_json
            end
          end
        end
        json
      rescue StandardError => e
        logger&.error(message: "Zip::File.open error: #{e.message}", details: e.backtrace)
        nil
      end

      # Open the JSON file and parse it into a Hash
      def parse_json(json_file_path:)
        json_file = File.open(json_file_path, 'r')
        JSON.parse(json_file.read)
      rescue JSON::ParserError => e
        logger&.error(message: "Invalid JSON in #{json_file_path}")
        nil
      end

      # Process the ROR JSON file
      def process_json(client:, table:, json:, details:, logger: nil)
        tstamp = details['tstamp']
        source = details['source']
        return 0 if details['start_at'].nil? || details['end_at'].nil?

        start_at = details['start_at'].to_i
        end_at = details['end_at'].to_i
        cntr = 0
        json[start_at..end_at].each do |hash|
          next unless hash.is_a?(Hash)

          successful = process_record(client:, table:, hash:, source:, tstamp:, logger:)
          cntr += 1 if successful
        end
        cntr
      end

      # Process the individual ROR record by creating/updating the equivalent record in our RDS database
      def process_record(client:, table:, hash:, source:, tstamp:, logger: nil)
        return false unless hash.is_a?(Hash) && !hash['id'].nil? && !hash['name'].nil?

        links = hash.fetch('links', [])
        domain = URI.parse(links.first).host.gsub('www.', '') if links.any?
        label = domain.nil? ? hash['name'] : "#{hash['name']} (#{domain})"
        fundref = hash.fetch('external_ids', {}).fetch('FundRef', {})
        funder = !fundref['preferred'].nil? || fundref.fetch('all', []).any?
        names = [hash['name']&.downcase&.strip, domain&.downcase&.strip]
        names = names + hash['aliases'] + hash['acronyms']
        kids = hash.fetch('relationships', []).select { |e| e['type']&.downcase == 'child' }.map { |c| c['id'] }
        parents = hash.fetch('relationships', []).select { |e| e['type']&.downcase == 'parent' }.map { |p| p['id'] }
        related = hash.fetch('relationships', []).select { |e| e['type']&.downcase == 'related' }.map { |p| p['id'] }
        wikipedia_url = hash['wikipedia_url']

        out = {
          PK: 'INSTITUTION',
          SK: hash['id'],
          label: label,
          name: hash['name'],
          searchable_names: names.flatten.compact.uniq,
          active: hash['status']&.downcase&.strip == 'active' ? 1 : 0,
          funder: funder ? 1 : 0,
          "_SOURCE": source,
          "_SOURCE_SYNCED_AT": tstamp
        }

        out[:domain] = domain unless domain.nil?
        out[:wikipedia_url] = wikipedia_url.length > 250 ? nil : wikipedia_url unless wikipedia_url.nil?
        out[:types] = hash['types'] if hash['types'].is_a?(Array)
        out[:children] = kids unless kids.nil? || kids.empty?
        out[:parents] = parents unless parents.nil? || parents.empty?
        out[:related] = related unless related.nil? || related.empty?
        out[:addresses] = hash['addresses'] if hash['addresses'].is_a?(Array)
        out[:relationships] = hash['relationships'] if hash['relationships'].is_a?(Array)
        out[:links] = hash['links'] if hash['links'].is_a?(Array)
        out[:aliases] = hash['aliases'] if hash['aliases'].is_a?(Array)
        out[:acronyms] = hash['acronyms'] if hash['acronyms'].is_a?(Array)
        out[:country] = hash['country'] if hash['country'].is_a?(Hash)
        out[:external_ids] = hash['external_ids'] if hash['external_ids'].is_a?(Hash)

        resp = client.put_item({ table_name: table, item: out,
                                 return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE' })
        logger.debug(message: "Added/Updated #{out[:SK]}", details: out) if logger.respond_to?(:debug)
        resp
      rescue StandardError => e
        logger&.error(message: "Unable to process ROR record: #{e.message}", details: { backtrace: e.backtrace, record: hash})
      end
    end
  end
end
