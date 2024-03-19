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

        # Establish the OpenSearch and Dynamo clients
        os_client = _open_search_connect(logger:)
        index = ENV['OPEN_SEARCH_INDEX']

        # Figure out which DMSPs we want to check on and then fetch all the unique ROR ids
        docs = _fetch_relevant_dmps(client: os_client, index:, logger:)
        rors = docs.map { |doc| doc.fetch('_source', {}).fetch('affiliation_ids', []) }.flatten.compact.uniq

        # Kick off harvesters for each unique ROR id
        rors.each do |ror|
          detail = {
            ror: ror,
            dmps: docs.select { |doc| doc.fetch('_source', {}).fetch('affiliation_ids', []).include?(ror) }
          }
          # Publish the change to the EventBridge
          publisher = Uc3DmpEventBridge::Publisher.new
          publisher.publish(source: 'HarvestableDmps', event_type: 'Harvest', dmp: {}, detail:, logger:)
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
        client = OpenSearch::Aws::Sigv4Client.new({ host: ENV['OPEN_SEARCH_DOMAIN'], log: true }, signer)
        logger&.debug(message: client&.info)
        client
      rescue StandardError => e
        puts "ERROR: Establishing connection to OpenSearch: #{e.message}"
        puts e.backtrace
      end

      # Fetch any DMPs that should be processed:
      #    - must have been registered
      #    - Those that were funded and have a `project: :end` within the next year
      #    - Those that were funded and have no `project: :end` BUT that were `:created` over a year ago
      #    - NOT those whose `project: :end` or `:created` dates are more than 3 years old!
      def _fetch_relevant_dmps(client:, index:, logger:)
        # three_years_ago = (Date.today - 1095).to_s
        # next_year = (Date.today + 365).to_s

        query = {
          query: {
            bool: {
              filter: [
                { exists: { field: 'registered' } },
                { exists: { field: 'funder_ids' } },
                { term: { funding_status: 'granted' } }
                # TODO: We will eventually want to timebox this as the size of our dataset grows.
                #       We don't want to search Datacite endlessly for a given DMP ID. This may
                #       involve recording the DOIs of those DMPs somewhere
                #{ range: { project_end: { gte: three_years_ago, lte: next_year } } }
              ]
            }
          }
        }
        resp = client.search(index:, body: query)

        # TODO: Handle pagination/scroll

        resp.fetch('hits', {}).fetch('hits', [])
      end
    end
  end
end
