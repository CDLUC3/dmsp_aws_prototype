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
  # A service that queries DataCite EventData
  class ExplorerDatacite
    SOURCE = 'DataCite Explorer'

    GRAPHQL_ENDPOINT = 'https://api.datacite.org/graphql'
    GRAPHQL_TIMEOUT_SECONDS = 30

    GRAPHQL_FAILURE = 'Unable to query the DataCite GraphQL API at this time.'

    MSG_BAD_REQUEST = 'No :augmenter_pk and/or no :run_id specified in the Event detail!'
    MSG_NO_AUGMENTER = 'No Augmenter could be found that matched the specified :augmenter_pk!'

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
        details = process_input(detail: event.fetch('detail', {}))

        # Setup the logger
        logger = _setup_logger(context:, details:)
        logger&.debug(message: 'Exploring the DataCite GraphQL API:', details:)

        # Bail if there is no augmenter defined or run_id
        return _respond(status: 400, message: MSG_BAD_REQUEST) if details[:augmenter_pk].nil? ||
                                                                  details[:run_id].nil?

        client = Uc3DmpDynamo::Client.new
        augmenter = fetch_augmenter(client:, id: details[:augmenter_pk], logger:)
        return _respond(status: 404, message: MSG_NO_AUGMENTER) if augmenter.nil?


          funders_to_scan
        end

        return _respond(status: 200, message: 'Success')
      end

      private

      def _setup_logger(context:, details:)
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : details[:run_id]
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)
      end

      def _respond(status:, message:, logger:)
        { statusCode: 200, body: "Success - #{processed}" }
      end
    end
  end
end
