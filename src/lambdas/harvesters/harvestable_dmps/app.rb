# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'date'

require 'opensearch-aws-sigv4'
require 'aws-sigv4'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'

module Functions
  # A service that queries OpenSearch to find DMP-IDs that are ready for harvesting
  class HarvestableDmps
    SOURCE = 'Harvestable DMPs'

    class << self
      def process(event:, context:)
        # No need to validate the source and detail-type because that is done by the EventRule
        details = event.fetch('detail', {})
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : nil
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # TODO: Eventually reenable this once we have OpenSearch in a stable situation
        # Establish the OpenSearch and Dynamo clients
        # os_client = _open_search_connect(logger:)
        # index = ENV['OPEN_SEARCH_INDEX']
        dynamo_client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        table = ENV['DYNAMO_INDEX_TABLE']

        # Figure out which DMSPs we want to check on and then fetch all the unique ROR ids
        # docs = _fetch_relevant_dmps(client: idx_client, index:, logger:)
        docs = _fetch_relevant_dmps_from_dynamo(client: dynamo_client, table:, logger:)
        logger.debug(message: 'Relevant DMP search results: ', details: docs) if logger.respond_to?(:debug)

        rors = docs.map { |doc| doc.fetch('affiliation_ids', []) }.flatten.compact.uniq

        # Kick off harvesters for each unique ROR id
        publisher = Uc3DmpEventBridge::Publisher.new
        rors.each do |ror|
          dmps = docs.select { |doc| doc.fetch('affiliation_ids', []).include?(ror) }

          # limit the number of DMPs we send at one time because SNS has a size limit
          dmps.each_slice(50) do |dmp_entries|
            _kick_off_harvester(ror:, dmps: dmp_entries, publisher:, logger:)
          end

          # Pause for a second. Publishing these messages kicks off multiple Lambda harvesters and we
          # do not want to inundate the external APIs with hundreds of queries at once
          sleep(2)
        end
        true
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: "Fatal error - #{e.message}", event_details: details }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
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

        logger.debug(message: "Establishing connection to #{ENV['OPEN_SEARCH_DOMAIN']}")
        client = OpenSearch::Aws::Sigv4Client.new({
          host: ENV['OPEN_SEARCH_DOMAIN'],
          retry_on_failure: 5,
          request_timeout: 120,
          log: true
        }, signer)
        logger&.debug(message: client&.info)
        client
      rescue StandardError => e
        puts "ERROR: Establishing connection to OpenSearch: #{e.message}"
        puts e.backtrace
      end

      def _kick_off_harvester(ror:, dmps:, publisher: nil, logger: nil)
        # Publish the change to the EventBridge
        publisher = Uc3DmpEventBridge::Publisher.new if publisher.nil?
        publisher.publish(source: 'HarvestableDmps', event_type: 'Harvest', dmp: {}, detail: { ror:, dmps: }, logger:)
      end

      # Instead of OpenSearch (for now) grab the relevant DMPs from our Dynamo INdex table
      def _fetch_relevant_dmps_from_dynamo(client:, table:, logger:)
        # Fetch all the relevant DMPs from the recursive function that scans the Dynamo Index table
        _dynamo_scan(client:, table:, logger:)
      end

      # Recursive function that goes and fetches every unique PK from the Dynamo table
      def _dynamo_scan(client:, table:, items: [], last_key: '', logger: nil)
        one_year_ago = (Date.today - 365).to_s  # 3 years is 1095
        next_year = (Date.today + 365).to_s
        expr = [
          'SK = :sk',
          'attribute_exists(registered) AND registered <> :not_empty',
          'attribute_exists(funder_ids) AND funder_ids <> :not_empty_array',
          'project_end BETWEEN :start_date AND :end_date'
        ]
        args = {
          table_name: table,
          consistent_read: false,
          projection_expression: 'PK, affiliation_ids',
          # expression_attribute_values: {
          #   ':sk': 'METADATA',
          #   ':not_empty': '',
          #   ':not_empty_array': [],
          #   ':start_date': one_year_ago,
          #   ':end_date': next_year
          # },
          # filter_expression: expr.join(' AND ')

          expression_attribute_values: {
            ':dmp_pks': [
=begin
              # Northwestern University
              'doi.org/10.48321/D10B3E54E4',
              'doi.org/10.48321/D1944C8215',
              'doi.org/10.48321/D139D84658',
              'doi.org/10.48321/D1A04A9B1D',

              # University of Colorado Boulder
              'doi.org/10.48321/D14F38aa13',
              'doi.org/10.48321/D1B581751F',

              # University of California, Santa Barbara
              'doi.org/10.48321/D1BAD5B94D',
              'doi.org/10.48321/D1FFE5D7FD',
              'doi.org/10.48321/D1A90CCC2B',
              'doi.org/10.48321/D154FA23E9',
=end
              # University of California, Berkeley
              'doi.org/10.48321/D114471AC3',
              'doi.org/10.48321/D1DF9DDDAF',
              'doi.org/10.48321/D18F9B93B8',
              'doi.org/10.48321/D1BA48FBC9',
              'doi.org/10.48321/D1CE350633',
=begin
              # University of California, Riverside
              'doi.org/10.48321/D14406894e',
              'doi.org/10.48321/D145457051',
              'doi.org/10.48321/D1FFBFF8FE',
              'doi.org/10.48321/D1FCB77AF0',
              'doi.org/10.48321/D13BEA529C',

              # Boston University
              'doi.org/10.48321/D1A04A9B1D'
=end
            ]
          },
          filter_expression: 'contains(:dmp_pks, dmp_id)'
        }
        args[:exclusive_start_key] = last_key unless last_key == ''
        logger.debug(message: 'Fetch relevant DMPs query args', details: args) if logger.respond_to?(:debug)
        resp = client.scan(args)
        p resp
        # p "Scanning - Item Count: #{resp.count}, Last Key: #{resp.last_evaluated_key}"
        items += resp.items
        return _dynamo_scan(client:, table:, items:, last_key: resp.last_evaluated_key) unless resp.last_evaluated_key.nil?

        items
      end

      # Fetch any DMPs that should be processed:
      #    - must have been registered
      #    - Those that were funded and have a `project: :end` within the next year
      #    - Those that were funded and have no `project: :end` BUT that were `:created` over a year ago
      #    - NOT those whose `project: :end` or `:created` dates are more than 3 years old!
      def _fetch_relevant_dmps(client:, index:, logger:)
        one_year_ago = (Date.today - 365).to_s
        next_year = (Date.today + 365).to_s

        query = {
          query: {
            bool: {
              filter: [
                { exists: { field: 'registered' } },
                { exists: { field: 'funder_ids' } },
                # { term: { funding_status: 'granted' } }
                # TODO: We will eventually want to timebox this as the size of our dataset grows.
                #       We don't want to search Datacite endlessly for a given DMP ID. This may
                #       involve recording the DOIs of those DMPs somewhere
                { range: { project_end: { gte: one_year_ago, lte: next_year } } }
              ]
            }
          }
        }

        # # Pilot partner specific tests for historical DMPs
        # query = {
        #   query: {
        #     ids: {
        #       values: [
        #         # Northwestern University
        #         'DMP#doi.org/10.48321/D10B3E54E4',
        #         'DMP#doi.org/10.48321/D1944C8215',
        #         'DMP#doi.org/10.48321/D139D84658',

        #         # University of Colorado Boulder
        #         'DMP#doi.org/10.48321/D14F38aa13',

        #         # University of California, Santa Barbara
        #         'DMP#doi.org/10.48321/D1BAD5B94D',
        #         'DMP#doi.org/10.48321/D1FFE5D7FD',
        #         'DMP#doi.org/10.48321/D1A90CCC2B',

        #         # University of California, Berkeley
        #         'DMP#doi.org/10.48321/D114471AC3',
        #         'DMP#doi.org/10.48321/D1DF9DDDAF',
        #         'DMP#doi.org/10.48321/D18F9B93B8',
        #         'DMP#doi.org/10.48321/D1BA48FBC9',
        #         'DMP#doi.org/10.48321/D1CE350633',

        #         # University of California, Riverside
        #         'DMP#doi.org/10.48321/D14406894e',
        #         'DMP#doi.org/10.48321/D145457051',
        #         'DMP#doi.org/10.48321/D1FFBFF8FE',
        #         'DMP#doi.org/10.48321/D1FCB77AF0',

        #         # Boston University
        #         'DMP#doi.org/10.48321/D1A04A9B1D'
        #       ]
        #     }
        #   }
        # }

        # Known DMP IDs with related works
        query = {
          query: {
            ids: {
              values: [
                'DMP#doi.org/10.48321/D1MK72',
                'DMP#doi.org/10.48321/D17598',
                'DMP#doi.org/10.48321/D17P5X',
                'DMP#doi.org/10.48321/D1F88S',
                'DMP#doi.org/10.48321/D1Z60Q',
                'DMP#doi.org/10.48321/D18S8D',
                'DMP#doi.org/10.48321/D12K5B',
                'DMP#doi.org/10.48321/D1BAD5B94D'
              ]
            }
          }
        }

        resp = client.search(index:, body: query, scroll: '2m', size: 25)
        recs = []
        counter = 0
        # Paginate through the search results
        while resp['hits']['hits'].size.positive?
          scroll_id = resp['_scroll_id']
          recs << resp.fetch('hits', {}).fetch('hits', [])
          resp = client.scroll(scroll: '1m', body: { scroll_id: scroll_id })
          logger.debug(message: "OpenSearch scroller - COUNTER: #{counter}, TOTAL_RECS: #{recs.length}")
          counter += 1
        end

        recs.flatten.uniq
      end
    end
  end
end
