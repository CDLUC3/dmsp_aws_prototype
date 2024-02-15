# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'opensearch-aws-sigv4'
require 'aws-sigv4'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-id'

module Functions
  # A service that queries DataCite EventData
  class TypeaheadIndexer
    SOURCE = 'Typeahead Dynamo Table Stream to OpenSearch'

    # Parameters
    # ----------
    # event: Hash, required
    #     DynamoDB Stream Event Input:
    #       {
    #         "eventID": "53041a9383eb551d8e1d5cc062aa7ebd",
    #         "eventName": "MODIFY",
    #         "eventVersion": "1.1",
    #         "eventSource": "aws:dynamodb",
    #         "awsRegion": "us-west-2",
    #         "dynamodb": {
    #           "ApproximateCreationDateTime": 1698878479.0,
    #           "Keys": {
    #             "SK": { "S": "https://ror.org/12345" },
    #             "PK": { "S": "INSTITUTION" }
    #           },
    #           "NewImage": {
    #             "external_ids": {
    #               "M": {
    #                 "FundRef": { "S": "0987654321" }
    #               }
    #             },
    #             "SK": { "S": "https://ror.org/12345" },
    #             "names": { "S": "Example University" },
    #             "PK": { "S": "INSTITUTION" },
    #             "label": { "S": "Example University (example.edu)" }
    #           },
    #           "SequenceNumber": "1157980700000000064369222776",
    #           "SizeBytes": 206,
    #           "StreamViewType": "NEW_IMAGE"
    #         },
    #         "eventSourceARN": "arn:aws:dynamodb:us-west-2:MY_ACCT:table/TABLE_ID/stream/2023-11-01T20:51:23.151"
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        records = event.fetch('Records', [])

        env = ENV.fetch('LAMBDA_ENV', 'dev')
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : event['id']
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        client = _open_search_connect(logger:) if records.any?
        record_count = 0

        records.each do |record|
          pk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('PK', {})['S']
          sk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('SK', {})['S']
          payload = record.fetch('dynamodb', {}).fetch('NewImage', {})
          logger&.error(message: 'For some reason this record had no PK/SK.', details: record) if pk.nil? || sk.nil?
          next if pk.nil? || sk.nil?

          # Process the record based on the PK type
          case pk
          when 'INSTITUTION'
            index = "#{env}-institutions"
            init_index(client:, index_name: index, logger:)
            body = process_institution_record(sk:, hash: payload, logger:)
          end
          next if body.nil? || index.nil?

          # Update the OpenSearch index based on the event type
          active = payload.fetch('active', {})['N'] == 1 ? 1 : 0
          case record['eventName']
          when 'REMOVE'
            logger&.info(message: "Removing OpenSearch document")
            client.delete(index:, id: sk)
          when 'MODIFY'
            # If the record has become inactive then remove it from the OpenSearch index
            if active == 'false'
              logger&.info(message: "Removing inactive OpenSearch document")
              client.delete(index:, id: sk)
            else
              logger&.info(message: "Updating OpenSearch document")
              client.index(index:, body:, id: sk, refresh: true)
            end
          else
            unless active == 'false'
              logger&.info(message: "Creating OpenSearch document")
              client.index(index:, body:, id: sk, refresh: true)
            end
          end

          record_count += 1
        rescue StandardError => e
          logger&.error(message: e.message, details: { backtrace: e.backtrace, record: record })
          next
        end

        logger&.info(message: "Processed #{record_count} records.")
        { statusCode: 200, body: "Processed #{record_count} records." }
      rescue StandardError => e
        puts "ERROR: Updating OpenSearch index: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: e.message }
      end

      private

      # Establish a connection to OpenSearch
      def _open_search_connect(logger:)
        # NOTE the AWS credentials are supplied to the Lambda at Runtime, NOT passed in by CloudFormation
        signer = Aws::Sigv4::Signer.new(
          service: 'es',
          region: ENV['AWS_REGION'],
          access_key_id: ENV['AWS_ACCESS_KEY_ID'],
          secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
          session_token: ENV['AWS_SESSION_TOKEN']
        )
        client = OpenSearch::Aws::Sigv4Client.new({ host: ENV['OPEN_SEARCH_DOMAIN'], log: true }, signer)
        logger&.debug(message: client&.info)
        client
      rescue StandardError => e
        puts "ERROR: Establishing connection to OpenSearch: #{e.message}"
        puts e.backtrace
      end

      # Create the index if it does not already exist
      def init_index(client:, index_name:, logger:)
        index_exists = client.indices.exists(index: index_name)
        return true if index_exists

        logger&.info(message: "Creating index '#{index_name}' because it does not exist")
        client.indices.create(index: index_name)
        true
      rescue StandardError => e
        logger&.error(message: "Unable to initialize index! #{e.message}", details: e.backtrace)
        false
      end

      # Convert an Institution record into an OpenSearch index document
      def process_institution_record(sk:, hash:, logger:)
        logger&.debug(message: 'Incoming Dynamo Item:', details: hash)

        doc = {
          identifier: sk,
          type: hash['PK'],
          funder: hash.fetch('funder', {})['N'] == 1 ? 1 : 0,
          source: hash.fetch('_SOURCE', {})['S']&.downcase
        }
        types = hash.fetch('types', {}).fetch('L', []).map { |item| item['S'] }
        doc[:types] = types.flatten.compact.uniq if types.any?

        # Collect all of the relationships
        parents = hash.fetch('parents', {}).fetch('L', []).map { |item| item['S'] }
        parents = [hash.fetch('parent', {})['S']] unless parents.any?
        doc[:parent] = parents.flatten.compact.uniq if parents.any?

        children = hash.fetch('children', {}).fetch('L', []).map { |kid| kid['S'] }
        doc[:children] = children.flatten.compact.uniq if children.any?

        related = hash.fetch('related', {}).fetch('L', []).map { |item| item['S'] }
        doc[:related] = related.flatten.compact.uniq if related.any?

        # Collect all of the identifiers
        ids = [sk]
        ext_ids = hash.fetch('external_ids', {}).fetch('M', {})
        ext_ids.each_key { |key| ids << ext_ids.fetch(key, {}).fetch('M', {}).fetch('preferred', {})['S'] }
        doc[:ids] = ids.flatten.compact.uniq

        # Collect all of the names
        names = [hash.fetch('name', {})['S']&.downcase, hash.fetch('domain', {})['S']&.downcase]
        names += hash.fetch('acronyms', {}).fetch('L', []).map { |item| item['S']&.downcase }
        names += hash.fetch('aliases', {}).fetch('L', []).map { |item| item['S']&.downcase }
        doc[:names] = names.flatten.compact.uniq

        # Collect the country name and code
        country_hash = hash.fetch('country', {}).fetch('M', {})
        doc[:country] = [country_hash.fetch('country_name', {})['S'], country_hash.fetch('country_code', {})['S']]
        doc
      end
    end
  end
end
