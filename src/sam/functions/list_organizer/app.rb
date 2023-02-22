# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'
require 'aws-sdk-sns'
require 'logger'

require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'

module Functions
  # Lambda function that is invoked by SNS and communicates with EZID to register/update DMP IDs
  # rubocop:disable Metrics/ClassLength
  class ListOrganizer
    SOURCE = 'EventBridge'

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
    #           "updater_is_provenance": false
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
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def process(event:, context:)
        detail = event.fetch('detail', {})
        json = detail.is_a?(Hash) ? detail : JSON.parse(detail)
        provenance_pk = json['dmphub_provenance_id']
        dmp_pk = json['PK']

        debug = SsmReader.debug_mode?
        pp "EVENT: #{event}" if debug
        pp "CONTEXT: #{context.inspect}" if debug

        Responder.log_error(source: SOURCE, message: "Just Testing this Event")

      rescue JSON::ParserError
        p "#{Messages::MSG_INVALID_JSON} - #{msg}"
        Responder.respond(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
      rescue Aws::Errors::ServiceError => e
        Responder.respond(status: 500, errors: "#{Messages::MSG_SERVER_ERROR} - #{e.message}", event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        p "FATAL -- MESSAGE: #{e.message}"
        p e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

    end
  end
  # rubocop:enable Metrics/ClassLength
end
