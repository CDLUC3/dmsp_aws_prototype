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
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-external-api'

module Functions
  # A service that fetches the latest ROR file
  class RorDownloader
    SOURCE = 'ROR Downloader'

    HARVESTER_PK = 'HARVESTER#ror'
    HARVESTER_SK = 'PROFILE'

    ALREADY_PROCESSED_MSG = 'No new file found on Zenodo!'
    BAD_DOWNLOAD_MSG = 'Zip archive failed the checksum validation!'
    DOWNLOAD_FAILURE_MSG = 'Unable to download the latest ROR file!'
    NO_HARVESTER_RECORD_MSG = 'No record found for `ror` in the Dynamo Typeahead table!'
    UNABLE_TO_DOWNLOAD_METADATA = 'Unable to fetch the latest ROR file metadata from Zenodo!'
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
    #         "detail": {}
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

        # Connect to Dynamo
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        table = ENV.fetch('DYNAMO_TABLE')

        # Fetch the ROR Source record from MySQL (or create it if this is the first time!)
        source = find_or_create_source(client:, table:, logger:)
        logger&.debug(message: 'Fetched harvester record from Dynamo.', details: source)
        logger&.error(message: NO_HARVESTER_RECORD_MSG) if source.nil?
        return { statusCode: 500, body: NO_HARVESTER_RECORD_MSG } if source.nil?

        # Fetch the ROR File metadata from Zenodo
        logger&.info(message: 'Fetching latest ROR archive file metadata.')
        file_metadata = fetch_zenodo_metadata(logger:)
        logger&.debug(message: 'Fetched the following file metadata from Zenodo', details: file_metadata)
        return { statusCode: 500, body: UNABLE_TO_DOWNLOAD_METADATA } if file_metadata.nil?

        # If the latest harvester metadata in the record matches what Zenodo has then we can skip
        logger&.info(message: ALREADY_PROCESSED_MSG) if source['last_metadata'] == file_metadata
        return { statusCode: 200, body: ALREADY_PROCESSED_MSG } if source['last_metadata'] == file_metadata

        # Download the Zip archive and extract the JSON from it
        tstamp = Time.now.utc.iso8601
        json = download_and_process_file(source:, file_metadata:, tstamp:, logger:)
        logger&.error(message: DOWNLOAD_FAILURE_MSG) if json.nil?
        return { statusCode: 500, body: DOWNLOAD_FAILURE_MSG } if json.nil?

        # Finally update the harvester record in RDS
        update_harvester_record(client:, table:, source:, metadata: file_metadata, tstamp:, logger:)
        alert_processors(source:, file_metadata:, json:, tstamp:, logger:)
        return { statusCode: 200, body: "Success - Downloaded and stashed Zip file in S3 and invoked processors." }
      rescue StandardError => e
        puts "Fatal error in RorHarvester! #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: "Fatal Server Error" }
      end

      private

      # Find the harvester's record in the RDS database
      def fetch_harvester_record(client:, table:, logger: nil)
        key = { PK: HARVESTER_PK, SK: HARVESTER_SK }
        resp = client.get_item({ table_name: table, key:, consistent_read: false,
                                 return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE' })

        logger.debug(message: "#{SOURCE} fetched DMP ID: #{key}") if logger.respond_to?(:debug)
        resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
      rescue Aws::Errors::ServiceError => e
        logger&.error(message: format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace))
        nil
      end

      # Update the harvester's record in the RDS database
      def update_harvester_record(client:, table:, source:, metadata: nil, tstamp: nil, logger: nil)
        source['last_metadata'] = metadata
        source['last_synced_at'] = tstamp
        resp = client.put_item({ table_name: table, item: source,
                                 return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE' })

        logger.debug(message: "#{SOURCE} put_item DMP ID: #{source['PK']}", details: source) if logger.respond_to?(:debug)
        resp
      rescue Aws::Errors::ServiceError => e
        logger&.error(message: format(MSG_DYNAMO_ERROR, msg: e.message, trace: e.backtrace))
        nil
      end

      # Fetch the ROR Harvester record from the RDS instance or create it
      def find_or_create_source(client:, table:, logger: nil)
        record = fetch_harvester_record(client:, table:, logger:)
        return record unless record.nil?

        # If it was not found, create the record and then return the new record
        source = { PK: HARVESTER_PK, SK: HARVESTER_SK, name: 'ROR Harvester', _TYPE: 'download' }
        update_harvester_record(client:, table:, source:)
        fetch_harvester_record(client:, table:, logger:)
      rescue StandardError => e
        logger&.error(message: "ERROR when trying to create a ROR harvester record in RDS: #{e.message}", details: e.backtrace)
        nil
      end

      # Fetch the latest ROR archive file metadata from Zenodo
      def fetch_zenodo_metadata(logger: nil)
        # Fetch the latest ROR metadata from Zenodo (the query will place the most recent version 1st)
        resp = Uc3DmpExternalApi::Client.call(url: ZENODO_METADATA_TARGET, method: :get,
                                              additional_headers: { host: HEADERS_HOST })

        # Extract the most recent file's metadata
        metadata = resp.fetch('hits', {}).fetch('hits', []).first&.fetch('files', [])&.last
        logger&.error(message: 'Unable to download ROR file metadata from Zenodo') if metadata.nil?
        url = metadata.fetch('links', {}).fetch('download', metadata.fetch('links', {})['self'])
        logger&.error(message: 'Zenodo file metadata is missing file download URL.') if url.nil?
        metadata[:download_url] = url
        JSON.parse(metadata.to_json)
      rescue JSON::ParserError => e
        logger&.error(message: 'Unable to parse JSON from Zenodo!', details: e.backtrace)
        nil
      end

      # Download the latest ROR zip file and process it
      def download_and_process_file(source:, file_metadata:, tstamp:, logger: nil)
        return nil unless file_metadata.is_a?(Hash)

        # Download and unzip the file
        zip_content = download_ror_file(source:, file_metadata:, tstamp:, logger:)
        logger&.error(message: DOWNLOAD_FAILURE_MSG, details: file_metadata) if zip_content.nil?
        return false if zip_content.nil?

        # Unzip and load the JSON content
        json = unzip_and_load_json(file_metadata:, zip_content:, logger:)
        logger&.error(message: UNZIP_PARSE_FAILURE_MSG, details: file_metadata) if json.nil?
        return false if json.nil?

        json
      end

      # Download the latest ROR file from S3 (if it is already there) or the target in the :file_metadata
      def download_ror_file(source:, file_metadata:, tstamp:, logger: nil)
        return nil unless file_metadata.is_a?(Hash)

        # Then see if we have the Zip file in S3
        key = "#{source['PK'].gsub('HARVESTER#', '')}/#{file_metadata['key']}"
        logger&.debug(message: "Checking S3 for ROR file: #{key}")
        zip_file = fetch_file_from_s3(key:, logger:)

        # If not already in S3, download the Zip archive
        zip_file.nil? ? download_zip_archive(source:, file_metadata:, tstamp:, logger:) : zip_file
      rescue StandardError => e
        logger&.error(message: "Unable to fetch the latest ROR zip file #{e.message}", details: e.backtrace)
        nil
      end

      # Download the ROR zip file from Zenodo
      def download_zip_archive(source:, file_metadata:, tstamp:, logger: nil)
        url = file_metadata['download_url']
        return nil if url.nil?

        # Fetch the file from Zenodo
        additional_headers = { host: HEADERS_HOST, Accept: 'application/json' }
        logger&.debug(message: "Downloading Zip file: #{url}", details: file_metadata)
        # Setting ligger to nil here because it fills up the log with the ZIP contents
        zip_file = Uc3DmpExternalApi::Client.call(url: url, method: :get, additional_headers:, logger: nil)
        return nil if zip_file.nil?

        # Stash a copy of the Zip archive in our S3 Bucket
        key = "#{source['PK'].gsub('HARVESTER#', '')}/#{file_metadata['key']}"
        stash_file_in_s3(source:, key:, file: zip_file, file_metadata:, tstamp:, logger:)
        zip_file
      rescue Uc3DmpExternalApi::ExternalApiError => e
        logger&.error(message: "Failure fetching ROR file from Zenodo: #{e.message}", details: e.backtrace)
        nil
      end

      # Fetch the latest ROR zip file from S3
      def fetch_file_from_s3(key:, logger: nil)
        client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        bucket = ENV['S3_BUCKET'].gsub('arn:aws:s3:::', '')

        logger&.debug(message: "Looking for #{key} in S3.")
        resp = client.get_object({ bucket:, key: })
        return nil if resp.nil? || !resp.content_length.positive?

        logger&.debug(message: 'Found ROR zip in S3')
        resp.body.is_a?(String) ? resp.body : resp.body.read
      rescue StandardError => e
        logger&.debug(message: "Failure fetching ROR zip file from S3: #{e.message}", details: e.backtrace)
        nil
      end

      # Stash the downloaded ROR zip file we got from Zenodo into our S3 bucket in case we need to process again
      def stash_file_in_s3(source:, key:, file:, file_metadata:, tstamp:, logger: nil)
        client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', nil))
        bucket = ENV['S3_BUCKET'].gsub('arn:aws:s3:::', '')
        tags = "SOURCE=#{source['PK'].gsub('HARVESTER#', '')}&ID=#{file_metadata['id']}&CHECKSUM=#{file_metadata['checksum']}&DOWNLOADED_ON=#{tstamp}"

        logger&.debug(message: "Stashing #{key} in S3.")
        resp = client.put_object({ body: file, bucket:, key:, tagging: tags })
        resp.successful? ? key : nil
      rescue StandardError => e
        logger&.error(message: "Failure stashing a copy of the ROR zip file in S3: #{e.message}", details: e.backtrace)
        nil
      end

      # Unzip the ROR file and extract the JSON file
      def unzip_and_load_json(file_metadata:, zip_content:, logger: nil)
        return nil if zip_content.nil? || !file_metadata.is_a?(Hash)

        # Get the name of the file we are interested in processing
        json_file_name = file_metadata['key']&.downcase&.gsub('.zip', '.json')

        logger&.debug(message: "Unzipping file ROR file and looking for #{json_file_name}")
        json = ''
        Dir.mktmpdir do |tmp_dir|
          zip_file_path = File.join(tmp_dir, 'downloaded.zip')
          File.open(zip_file_path, 'wb') { |file| file.write(zip_content) }
          # Validate the file based on the checksum in the metadata and then return the filename
          valid = validate_downloaded_file(file_path: zip_file_path,
                                          checksum: file_metadata['checksum']&.split(':')&.last)
          logger&.error(message: BAD_DOWNLOAD_MSG, details: file_metadata) unless valid
          return nil unless valid

          Zip::File.open(zip_file_path) do |files|
            files.each do |entry|
              next if File.exist?(entry.name)

              f_path = File.join(tmp_dir, entry.name)
              FileUtils.mkdir_p(File.dirname(f_path))
              files.extract(entry, f_path) unless File.exist?(f_path)
              is_json = entry.name.downcase.include?(json_file_name)
              json = parse_json(json_file_path: f_path) if is_json
            end
          end
        end
        json
      rescue StandardError => e
        logger&.error(message: "Zip::File.open error: #{e.message}", details: e.backtrace)
        nil
      end

      # Compare the ROR zip file's checksum against what they have specified in the file metadata record
      def validate_downloaded_file(file_path:, checksum:)
        return false if file_path.nil? || checksum.nil? || !File.exist?(file_path)

        possible_checksums = [
          Digest::SHA1.file(file_path).to_s,
          Digest::SHA256.file(file_path).to_s,
          Digest::SHA512.file(file_path).to_s,
          Digest::MD5.file(file_path).to_s
        ]
        possible_checksums.include?(checksum)
      end

      # Open the JSON file and parse it into a Hash
      def parse_json(json_file_path:)
        json_file = File.open(json_file_path, 'r')
        JSON.parse(json_file.read)
      rescue JSON::ParserError => e
        logger&.error(message: "Invalid JSON in #{json_file_path}")
        nil
      end

      # Send signals to processors
      def alert_processors(source:, file_metadata:, json:, tstamp:, logger: nil)
        return false unless json.is_a?(Array) && !file_metadata['key'].nil?

        client = Aws::EventBridge::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        total_recs = json.length
        records_allowed = ENV.fetch('PROCESSOR_RECORD_COUNT', 50000).to_i
        return false unless total_recs > 0

        # Calculate the number of processors to kick off
        processors = 1 if total_recs <= records_allowed || records_allowed <= 0
        processors = (total_recs / records_allowed.to_f).ceil.round if processors.nil?
        logger&.info(message: "Total records: #{total_recs}, Allowed per processor: #{records_allowed}, nbr processors needed: #{processors}")

        last_rec = 0
        events = []
        # Format a message for each processor with the start/end record numbers
        processors.times.each do |proc|
          target_end = last_rec + records_allowed
          target_end = total_recs if target_end > total_recs

          events << {
            time: Time.now.utc.iso8601,
            source: "#{ENV.fetch('DOMAIN', nil)}:lambda:event_publisher",
            detail_type: 'RorProcessor',
            detail: {
              zip_file: "#{source['PK'].gsub('HARVESTER#', '')}/#{file_metadata['key']}",
              source: source['PK'].gsub('HARVESTER#', '')&.upcase,
              tstamp: tstamp,
              start_at: last_rec,
              end_at: target_end > total_recs ? total_recs : target_end
            }.to_json,
            event_bus_name: ENV.fetch('EVENT_BUS_NAME', nil)
          }
          last_rec = target_end + 1
        end
        return false if events.empty?

        # Publish the Events
        logger&.info(message: "RorDownloader published events", details: events)
        resp = client.put_events({ entries: events })
        true
      end
    end
  end
end
