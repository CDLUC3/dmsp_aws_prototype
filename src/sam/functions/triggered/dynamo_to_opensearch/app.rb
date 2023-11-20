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

    OPEN_SEARCH_DOMAIN = ''
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
          next if pk.nil? || sk.nil? || sk != Uc3DmpId::Helper::DMP_LATEST_VERSION

          logger&.debug(message: "Processing change to DynamoDB record #{pk}", details: record)

          case record['eventName']
          when 'REMOVE'
            p "Removing OpenSearch record"
          when 'MODIFY'
            p "Updating OpenSearch record"
          else
            p "Creating OpenSearch record"
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
          url: OPEN_SEARCH_DOMAIN,
          retry_on_failure: 5,
          request_timeout: 120,
          log: logger&.level == 'debug'
        )
      end
    end
  end
end
