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
    SOURCE = 'SNS Topic - Notification'

    # Parameters
    # ----------
    # event: Hash, required
    #     API Gateway Lambda Proxy Input Format
    #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
    #     {
    #       Records: [
    #         {
    #           "EventSource": "aws:sns",
    #           "EventVersion": "1.0",
    #           "EventSubscriptionArn": "arn:aws:sns:us-west-2:blah-blah-blah",
    #           "Sns": {
    #             "Type": "Notification",
    #             "MessageId": "a7ba6aaf-0d52-5d94-968e-311e0661231f",
    #             "TopicArn": "arn:aws:sns:us-west-2:yadda-yadda-yadda",
    #             "Subject": "DmpCreator - register DMP ID - DMP#doi.org/10.80030/D1.51C5D8E2",
    #             "Message": "{\"dmp\":\"DMP#doi.org/10.80030/D1.51C5D8E2\",
    #                          \"provenance\":\"PROVENANCE#example\"}",
    #             "Timestamp": "2022-09-30T15:19:15.182Z",
    #             "SignatureVersion":"1",
    #             "Signature":"Jeh4PdtFzpNtnRpLrNYhO9C5JYfjGPiLQIoW+0RykbVroSIetNILviPLlUNLGXlbbm...==",
    #             "SigningCertUrl": "https://sns.us-west-2.amazonaws.com/SimpleNotificationService-foo.pem",
    #             "UnsubscribeUrl": "https://sns.us-west-2.amazonaws.com/?Action=Unsubscribe...",
    #             "MessageAttributes": {}
    #           }
    #         }
    #       ]
    #     }"
    #
    #    Message should contain a parseable JSON string that contains:
    #      {
    #        "provenance": "PROVENANCE#example",
    #        "dmp": "DMP#doi.org/10.80030/D1.51C5D8E2"
    #      }

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
        msg = event.fetch('Records', []).first&.fetch('Sns', {})&.fetch('Message', '')
        json = msg.is_a?(Hash) ? msg : JSON.parse(msg)
        provenance_pk = json['provenance']
        dmp_pk = json['dmp']

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp "EVENT: #{event}" if debug
        pp "CONTEXT: #{context.inspect}" if debug

        if provenance_pk.nil? || dmp_pk.nil?
          return Responder.respond(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
        end

        # Load the Provenance info

        # Verify that the Provenance has a callback URL defined

        # Load the DMP metadata
        table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
        p "TABLE: #{table}, CLIENT: #{client}"

        # Send the latest DMP metadata to the Prvenance system's calllback URL

        Responder.respond(status: 200, errors: Messages::MSG_SUCCESS, event: event)
      rescue JSON::ParserError
        p "#{Messages::MSG_INVALID_JSON} - MESSAGE: #{msg}"
        Responder.respond(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
      rescue Aws::Errors::ServiceError => e
        p "#{e.message} - PROVENANCE: #{provenance_pk}, DMP: #{dmp_pk}"
        p e.backtrace
        Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        p "FATAL: #{e.message} - PROVENANCE: #{provenance_pk}, DMP: #{dmp_pk}"
        p e.backtrace
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
