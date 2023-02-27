# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'
require 'aws-sdk-sns'
require 'httparty'

require 'responder'
require 'ssm_reader'

module Functions
  # The handler for POST /dmps/validate
  class ProvenanceNotifier
    SOURCE = 'EventBridge - Notify Provenance'
    NO_NOTIFICATION = 'Provenance system was the updater. No need to notify.'
    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "DMP change",
    #         "source": "dmphub-dev.cdlib.org:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "PK": "DMP#doi.org/10.12345/ABC123",
    #           "SK": "VERSION#latest",
    #           "dmproadmap_links": {
    #             "download": "https://example.com/api/dmps/12345.pdf",
    #           },
    #           "dmphub_updater_is_provenance": false
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

    # Returns
    # ------
    # statusCode: Integer, required
    # body: String, required (JSON parseable)
    #     API Gateway Lambda Proxy Output Format: dict
    #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
    #
    #     { "statusCode": 200, "body": "{\"message\":\"Success\""}" }
    #
    class << self
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def process(event:, context:)
        detail = event.fetch('detail', {})
        json = detail.is_a?(Hash) ? detail : JSON.parse(detail)

        provenance_pk = json['dmphub_provenance_id']
        should_notify = json.fetch('dmphub_updater_is_provenance', 'true').to_s.downcase != 'true'
        dmp_pk = json['PK']

        # We don't want to callback to the provenance if it was the one who made the change
        return Responder.respond(status: 200, errors: NO_NOTIFICATION, event: event) unless should_notify

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp "EVENT: #{event}" if debug
        pp "CONTEXT: #{context.inspect}" if debug

        if provenance_pk.nil? || dmp_pk.nil?
          return Responder.respond(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
        end

        # Load the Provenance info

        # Load the DMP metadata
        table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
        dmp = load_dmp(provenance_pk: provenance_pk, dmp_pk: dmp_pk, table: table, client: client, debug: debug)
        if dmp.nil?
          return Responder.respond(status: 404, errors: Messages::MSG_DMP_NOT_FOUND,
                                   event: event)
        end

        # Verify that the Provenance has a callback URL defined

        # Send the latest DMP metadata to the Prvenance system's calllback URL

        Responder.respond(status: 200, errors: Messages::MSG_SUCCESS, event: event)
      rescue JSON::ParserError
        Responder.log_message(source: SOURCE, message: Messages::MSG_INVALID_JSON)
        Responder.respond(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
      rescue Aws::Errors::ServiceError => e
        msg = "#{e.message} - PROVENANCE: #{provenance_pk}, DMP: #{dmp_pk}"
        Responder.log_message(source: SOURCE, message: msg, details: e.backtrace)
        Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message} - PROVENANCE: #{provenance_pk}, DMP: #{dmp_pk}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      # Fetch the DMP JSON from the DyanamoDB Table
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def load_dmp(provenance_pk:, dmp_pk:, table:, client:, debug: false)
        return nil if table.nil? || client.nil? || provenance_pk.nil? || dmp_pk.nil?

        # Fetch the Provenance first
        prov_finder = ProvenanceFinder.new(table_name: table, client: client, debug_mode: debug)
        response = prov_finder.provenance_from_pk(p_key: provenance_pk)
        return nil unless response[:status] == 200

        # Fetch the DMP
        provenance = response[:items].first
        dmp_finder = DmpFinder.new(provenance: provenance, table_name: table, client: client, debug_mode: debug)
        response = dmp_finder.find_dmp_by_pk(p_key: dmp_pk, s_key: KeyHelper::DMP_LATEST_VERSION)
        response[:status] == 200 ? response[:items].first['dmp'] : nil
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end
