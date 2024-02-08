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

module Functions
  # A service that queries DataCite EventData
  class TypeaheadToOpensearch
    SOURCE = 'Typeaheads DynamoDb Table Stream to OpenSearch'

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
    #             "SK": { "S": "https://ror.org/01cwqze88" },
    #             "PK": { "S": "INSTITUTION" }
    #           },
    #           "NewImage": {
    #             "PK": { "S": "INSTITUTION" },
    #             "SK": { "S": "https://ror.org/01cwqze88" },
    #             "description": { "S": "" },
    #             "source": { "S": "ROR" },
    #             "types": { "SS": [{ "S", "Government" }],
    #             "acronyms": { "SS": [{ "S", "NIH" }] },
    #             "country": {
    #               "M": {
    #                 "country_name": { "S": "United States" },
    #                 "country_code": { "S": "US" },
    #               }
    #             },
    #             "status": { "S": "active" },
    #             "name": { "S": "National Institutes of Health" },
    #             "external_ids": {
    #               "M": {
    #                 "ISNI": { "S": "0000 0001 2297 5165" },
    #                 "FundRef": { "S": "100000002" },
    #                 "Wikidata": { "SS": [{ "S": "Q390551" }, { "S": "Q6973636" }] },
    #                 "GRID": { "S": "grid.94365.3d" },
    #               }
    #             },
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
          payload = record.fetch('dynamodb', {}).fetch('NewImage', {})
          next if pk.nil? || sk.nil? || payload.nil?

          logger&.debug(message: "Processing change to DynamoDB record #{pk}", details: record)

          case record['eventName']
          when 'REMOVE'
            logger&.info(message: "Removing OpenSearch record")
          when 'MODIFY'
            logger&.info(message: "Updating OpenSearch record")
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: _typeahead_to_os_doc(hash: payload, logger:),
              id: sk,
              refresh: true
            )
          else
            logger&.info(message: "Creating OpenSearch record")
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: _typeahead_to_os_doc(hash: payload, logger:),
              id: sk,
              refresh: true
            )
          end

          record_count += 1
        end

        puts client.search(body: { query: { match: { name: 'national' } } })

        logger&.info(message: "Processed #{record_count} records.")
        "Processed #{record_count} records."
      rescue StandardError => e
        puts "ERROR: Updating OpenSearch index: #{e.message}"
        puts e.backtrace
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

        # Create the index if it does not already exist
        index_exists = client.indices.exists(index: ENV['OPEN_SEARCH_INDEX'])
        logger&.info(message: "Creating index '#{ENV['OPEN_SEARCH_INDEX']}' because it does not exist") unless index_exists
        client.indices.create(index: ENV['OPEN_SEARCH_INDEX']) unless index_exists

        client
      rescue StandardError => e
        puts "ERROR: Establishing connection to OpenSearch: #{e.message}"
        puts e.backtrace
      end

      # Convert the incoming item into an OpenSearch doc
      def _typeahead_to_os_doc(hash:, logger: nil)
        parts = { names: [], ids: [], websites: [], descriptions: [], country: {} }
        parts = _parts_from_typeahead(parts_hash: parts, hash:)
        parts.merge({ TYPE: hash.fetch('PK', {})['S'], SK: hash.fetch('SK', {})['S'] })
        parts
      end

      # Extract the parts from the typeahead item
      def _parts_from_typeahead(parts_hash:, hash:)
        names = _process_dynamo_struct(hash: hash.fetch('name', hash['names']))
        titles = _process_dynamo_struct(hash: hash.fetch('title', hash['titles']))
        aliases = _process_dynamo_struct(hash: hash.fetch('alias', hash['aliases']))
        acronyms = _process_dynamo_struct(hash: hash.fetch('acronym', hash['acronyms']))
        parts_hash[:names] = [names, titles, aliases, acronyms].flatten.compact.uniq

        id = _process_dynamo_struct(hash: hash['SK'])
        ids = _process_dynamo_struct(hash: hash.fetch('id', hash.fetch('ids', hash.fetch('identifier', hash['identifiers']))))
        ext_ids = _process_dynamo_struct(hash: hash.fetch('external_id', hash.fetch('external_ids', hash['external_identifiers'])))
        parts_hash[:ids] = [id, ids, ext_ids].flatten.compact.uniq

        links = _process_dynamo_struct(hash: hash.fetch('link', hash['links']))
        sites = _process_dynamo_struct(hash: hash.fetch('site', hash.fetch('sites', hash.fetch('website', hash['websites']))))
        homepage = _process_dynamo_struct(hash: hash.fetch('homepage', hash['home_page']))
        parts_hash[:websites] = [links, sites, homepage].flatten.compact.uniq

        descriptions = _process_dynamo_struct(hash: hash.fetch('description', hash['descriptions']))
        abstracts = _process_dynamo_struct(hash: hash.fetch('abstract', hash['abstracts']))
        parts_hash[:descriptions] = [descriptions, abstracts].flatten.compact.uniq

        parts_hash[:country] = _process_dynamo_struct(hash: hash.fetch('country', hash['countries']))
        parts_hash
      end

      def _process_dynamo_struct(hash:)
        return nil unless hash.is_a?(Hash)
        # Check each Dynamo Attribute type: https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_AttributeValue.html
        return nil unless hash['B'].nil? && hash['BS'].nil? && hash['NULL'].nil?
        return hash['BOOL'].to_s unless hash['B'].nil?
        return hash['S'].downcase.strip unless hash['S'].nil?
        return hash['N'].to_s unless hash['N'].nil?
        return hash['SS'].map { |entry| entry&.downcase&.strip } unless hash['SS'].nil?
        return hash['NS'].map { |entry| entry&.to_s } unless hash['NS'].nil?

        hash['L'].nil? ? _extract_items_from_list(list: hash['L']) : _extract_items_from_map(map: hash['M'])
      end

      def _extract_items_from_list(list:)
        return nil unless list.is_a?(Array)

        list.map { |hash| _process_dynamo_struct(hash: hash) }
      end

      def _extract_items_from_map(map:)
        return nil unless map.is_a?(Hash)

        map.keys.each { |key| _process_dynamo_struct(hash: hash[key]) }
      end
    end
  end
end
