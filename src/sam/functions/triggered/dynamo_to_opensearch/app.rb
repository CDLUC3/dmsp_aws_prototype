# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'opensearch'

require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-id'

module Functions
  # A service that queries DataCite EventData
  class DynamoToOpensearch
    SOURCE = 'DynamoDb Table Stream to OpenSearch'

    OPEN_SEARCH_INDEX = ''


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
    #             "SK": { "S": "VERSION#latest" },
    #             "PK": { "S": "DMP#stream_test_1" }
    #           },
    #           "NewImage": {
    #             "contact": {
    #               "M": {
    #                 "name": { "S": "Riley, Brian" },
    #                 "contact_id": {
    #                   "M": {
    #                     "identifier": { "S": "https://orcid.org/0000-0001-9870-5882" },
    #                     "type": { "S": "orcid" }
    #                   }
    #                 }
    #               }
    #             },
    #             "SK": { "S": "VERSION#latest" },
    #             "description": { "S": "Update 4" },
    #             "PK": { "S": "DMP#stream_test_1" },
    #             "title": { "S": "Stream test 1" }
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

        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : event['id']
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        client = _open_search_connect(logger:) if records.any?
        record_count = 0

        records.each do |record|
          pk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('PK', {})['S']
          sk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('SK', {})['S']
          payload = record.fetch('NewImage', {})
          next if pk.nil? || sk.nil? || payload.nil? || sk != Uc3DmpId::Helper::DMP_LATEST_VERSION

          logger&.debug(message: "Processing change to DynamoDB record #{pk}", details: record)

          case record['eventName']
          when 'REMOVE'
            p "Removing OpenSearch record"
          when 'MODIFY'
            p "Updating OpenSearch record"
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: dmp_to_os_doc(hash: payload),
              id: pk,
              refresh: true
            )
          else
            p "Creating OpenSearch record"
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: dmp_to_os_doc(hash: payload),
              id: pk,
              refresh: true
            )
          end

          record_count += 1
        end

        logger&.info(message: "Processed #{record_count} records.")
        "Processed #{record_count} records."
      end

      private

      # Establish a connection to OpenSearch
      def _open_search_connect(logger:)
        OpenSearch::Client.new(
          url: ENV['OPEN_SEARCH_DOMAIN'],
          retry_on_failure: 5,
          request_timeout: 120,
          log: logger&.level == 'debug'
        )
      end

      # Convert the incoming DynamoStream payload to the OpenSearch index format
      # Incoming:
      #   {
      #     "contact": {
      #       "M": {
      #         "name": { "S": "Riley, Brian" },
      #         "contact_id": {
      #           "M": {
      #             "identifier": { "S": "https://orcid.org/0000-0001-0001-0001" },
      #             "type": { "S": "orcid" }
      #           }
      #         }
      #       }
      #     },
      #     "SK": { "S": "VERSION#latest" },
      #     "description": { "S": "Update 4" },
      #     "PK": { "S": "DMP#stream_test_1" },
      #     "title": { "S": "Stream test 1" }
      #   }
      #
      # Index Doc:
      #   {
      #     "dmp_id": "stream_test_1",
      #     "title": "Stream test 1",
      #     "description": "Update 4",
      #     "contact_id": "https://orcid.org/0000-0001-0001-0001"
      #     "contact_name": "Riley"
      #   }
      def dmp_to_os_doc(hash:)
        parts = { people: [], people_ids: [], affiliations: [], affiliation_ids: [] }
        parts = parts_from_dmp(hash:)
        parts.merge({
          dmp_id: Uc3DmpId::Helper.pk_to_dmp_id(p_key: hash.fetch('PK', {})['S']),
          title: hash.fetch('title', {})['S']&.downcase,
          description: hash.fetch('description', {})['S']&.downcase
        })
      end

      # Convert the contact section of the Dynamo record to an OpenSearch Document
      def parts_from_dmp(hash:)
        contributors = hash.fetch('contributor', []).map { |c| c.fetch('M', {})}

        # Process the contact
        parts_hash = parts_from_person(parts_hash:, hash: hash.fetch('contact', {}).fetch('M', {}))
        # Process each contributor
        hash.fetch('contributor', []).map { |c| c.fetch('M', {})}.each do |contributor|
          parts_hash = parts_from_person(parts_hash:, hash: contributor)
        end

        # Deduplicate and remove nils and convert to lower case
        parts_hash.each_key { |key| parts_hash[key] = parts_hash[key].compact.uniq.map(&:downcase) }
        parts_hash
      end

      # Convert the person metadata for OpenSearch
      def parts_from_person(parts_hash:, hash:)
        return nil unless hash.is_a?(Hash) && hash.keys.any?

        id = hash.fetch('contact_id', hash.fetch('contributor_id', {}))['M']
        a_id = hash.fetch('dmproadmap_affiliation', {})['M']

        parts_hash[:people] << hash.fetch('name', {})['S']
        parts_hash[:people] << hash.fetch('mbox', {})['S']
        parts_hash[:affiliations] << affil.fetch('name', {})['S']

        parts_hash[:people_ids] << id.fetch('identifier', {})['S']
        parts_hash[:affiliation_ids] << a_id.fetch('affiliation_id', {}).fetch('M', {}).fetch('identifier', {})['S']
        parts_hash
      end
    end
  end
end
