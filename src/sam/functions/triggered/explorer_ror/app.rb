# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'
require 'digest'
require 'zip'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-external-api'
require 'uc3-dmp-s3'

module Functions
  # A service that fetches the latest ROR file
  class ExplorerRor
    SOURCE = 'ROR Explorer'
    EXPLORER_ID = 'ror'

    ALREADY_PROCESSED_MSG = 'No new file found on Zenodo!'
    BAD_DOWNLOAD_MSG = 'Zip archive failed the checksum validation!'
    DOWNLOAD_FAILURE_MSG = 'Unable to download the latest ROR file!'
    NO_EXPLORER_RECORD_MSG = 'No record found for `RESOURCETYPE = "explorer" && ID = "ror"`'

    ZIP_FILE_NAME = "#{Dir.pwd}/ror-latest.zip"

    DOWNLOAD_HOST = 'zenodo.org'
    UNZIP_TARGET = 'explorer/files'

    ROR_PREFIX = 'https://ror.org'
    FUNDREF_PREFIX = 'https://doi.org/10.13039/'

    ROR_PREFIX_REGEX = %r{(https?:/)?/?ror\.org/}
    FUNDREF_PREFIX_REGEX = %r{(https?:/)?/?doi\.org/10\.13039/}

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

        # Load the explorer record
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        explorer_details = fetch_explorer(client:, logger:)
        return { statusCode: 500, body: 'Invalid Explorer' } if explorer_details.nil? ||
                                                                explorer_details['ID'] != EXPLORER_ID

        # Fetch the latest file metadata from Zenodo
        metadata = fetch_zenodo_metadata(explorer_details:, logger:)
        already_processed = explorer_details['file_metadata'] == metadata
        logger&.debug(message: ALREADY_PROCESSED_MSG, details: metadata) if already_processed
        return { statusCode: 200, body: ALREADY_PROCESSED_MSG } if metadata.nil? || already_processed

        # Download the file and proces it (assuming we haven't already seen that version)
        explorer_details['file_metadata'] = metadata
        processed = fetch_and_process_file(client:, explorer_details:, logger:)

        update_explorer(client:, explorer_details:, logger:) if processed
        return { statusCode: 200, body: "Success - #{processed}" }
      end

      private

      # Fetch the record about this explorer
      def fetch_explorer(client:, logger:)
        resp = client.get_item({
          table_name: ENV.fetch('DYNAMO_TABLE', nil),
          key: { RESOURCE_TYPE: 'EXPLORER', ID: EXPLORER_ID },
          consistent_read: false,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        })
        logger&.debug(message: "#{SOURCE} fetched EXPLORER: #{EXPLORER_ID}")
        resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
      end

      # Update the file metadata and timestamp on the explorer record
      def update_explorer(client:, explorer_details:, logger:)
        explorer_details['last_loaded_at'] = Time.now.utc.iso8601
        resp = client.put_item({
          table_name: ENV.fetch('DYNAMO_TABLE', nil),
          item: explorer_details,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        })
        logger&.debug(message: "#{SOURCE} put_item EXPLORER: #{EXPLORER_ID}", details: explorer_details)
        resp
      end

      # Fetch the latest Zenodo metadata for ROR files
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def fetch_zenodo_metadata(explorer_details:, logger:)
        # Fetch the latest ROR metadata from Zenodo (the query will place the most recent version 1st)
        resp = Uc3DmpExternalApi::Client.call(url: explorer_details['download_uri'], method: :get,
                                              additional_headers: { host: DOWNLOAD_HOST }, logger:)
        logger&.error(message: DOWNLOAD_FAILURE_MSG, details: resp) if resp.nil?
        return nil if resp.nil?

        # Extract the most recent file's metadata
        file_metadata = resp.fetch('hits', {}).fetch('hits', []).first&.fetch('files', [])&.last
        logger&.error(message: DOWNLOAD_FAILURE_MSG) if file_metadata.nil? ||
                                                        file_metadata.fetch('links', {})['download'].nil?
        file_metadata
      rescue JSON::ParserError => e
        log&.error(message: e.message)
        nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def fetch_and_process_file(client:, explorer_details:, logger:)
        return nil unless explorer_details.is_a?(Hash) && explorer_details['file_metadata'].is_a?(Hash)

        # Download and unzip the file
        zip_content = download_ror_file(explorer_details:, logger:)
        logger&.error(message: DOWNLOAD_FAILURE_MSG, details: explorer_details) if zip_content.nil?
        return false if zip_content.nil?

        # Unzip and load the JSON content
        json = unzip_and_load_json(explorer_details:, zip_content:, logger:)
        logger&.error(message: DOWNLOAD_FAILURE_MSG, details: explorer_details) if json.nil?
        return false if json.nil?

        process_json(client:, explorer_details:, json:, logger:)
      end

      # Download the latest ROR data
      def download_ror_file(explorer_details:, logger:)
        return nil unless explorer_details.is_a?(Hash) && !explorer_details['file_metadata'].nil?

        # First try to fetch the file from S3
        zip_file = fetch_file_from_s3(explorer_details:, logger:)
        # If not already in S3, download the Zip archive
        zip_file.nil? ? download_zip_archive(explorer_details:, logger:) : zip_file
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        nil
      end

      # Fetch the ZIP archive from Zenodo
      def download_zip_archive(explorer_details:, logger:)
        url = explorer_details.fetch('file_metadata', {}).fetch('links', {})['download']
        return nil if url.nil?

        # Fetch the file from Zenodo
        additional_headers = { host: DOWNLOAD_HOST, Accept: 'application/json' }
        zip_file = Uc3DmpExternalApi::Client.call(url: url, method: :get, additional_headers:, logger:)
        return nil if zip_file.nil?

        # Stash a copy of the Zip archive in our S3 Bucket
        stash_file_in_s3(file: zip_file, explorer_details:, logger:)
        zip_file
      end

      # Write the file to S3
      def stash_file_in_s3(file:, explorer_details:, logger:)
        object_key = Uc3DmpS3::Client.put_resource_file(file: file, explorer_details:)
        logger&.error(message: Uc3DmpS3::Client::MSG_S3_FAILURE, details: explorer_details) if object_key.nil?
        object_key
      rescue Uc3DmpS3::ClientError => e
        logger&.error(message: e.message, details: explorer_details)
        nil
      rescue StandardError => e
        logger&.error(message: "Uc3DmpS3::Client.put_resource_file error: #{e.message}")
        nil
      end

      # Pull the Zip archive from S3
      def fetch_file_from_s3(explorer_details:, logger:)
        object_key = "#{explorer_details['ID']}_#{explorer_details.fetch('file_metadata', {})['filename']}"
        Uc3DmpS3::Client.get_resource_file(key: object_key)
      rescue Uc3DmpS3::ClientError => e
        logger&.debug(message: e.message, details: explorer_details)
        nil
      end

      # Process the ROR JSON file
      def process_json(client:, explorer_details:, json:, logger:)
        cntr = 0
        total = json.length
        json.each do |hash|
          cntr += 1
          logger&.debug(message: "Processed #{cntr} out of #{total} records") if (cntr % 1000).zero?
          next unless hash.is_a?(Hash)

          p hash if cntr <= 10
          # process_ror_record(record: hash, time: file_time)
        end
        true
      end

      # Unzips the specified file
      def unzip_and_load_json(explorer_details:, zip_content:, logger:)
        return nil if zip_content.nil? || !explorer_details.is_a?(Hash) ||
                      explorer_details.fetch('file_metadata', {})['filename'].nil?

        # Get the name of the file we are interested in
        json_file_name = explorer_details['file_metadata']['filename']&.downcase&.gsub('.zip', '.json')

        json = ''
        Dir.mktmpdir do |tmp_dir|
          zip_file_path = File.join(tmp_dir, 'downloaded.zip')
          File.open(zip_file_path, 'wb') { |file| file.write(zip_content) }
          # Validate the file based on the checksum in the metadata and then return the filename
          valid = validate_downloaded_file(file_path: zip_file_path,
                                           checksum: explorer_details['file_metadata']['checksum'])
          logger&.error(message: BAD_DOWNLOAD_MSG, details: explorer_details) unless valid
          return nil unless valid

          Zip::File.open(zip_file_path) do |files|
            files.each do |entry|
              next if File.exist?(entry.name)

              f_path = File.join(tmp_dir, entry.name)
              FileUtils.mkdir_p(File.dirname(f_path))
              files.extract(entry, f_path) unless File.exist?(f_path)

              is_json = entry.name.downcase.include?(json_file_name)

              p "NON-JSON file: #{f_path}" unless is_json

              json = parse_json(json_file_path: f_path) if is_json
            end
          end
        end
        json
      rescue StandardError => e
        logger&.error(message: "Zip::File.open error: #{e.message}")
        nil
      end

      # Open and parse the
      def parse_json(json_file_path:)
        json_file = File.open(json_file_path, 'r')
        JSON.parse(json_file.read)
      rescue JSON::ParserError => e
        logger&.error(message: 'Invalid JSON!')
        nil
      end

      # Determine if the downloaded file matches the expected checksum
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
    end
  end
end
