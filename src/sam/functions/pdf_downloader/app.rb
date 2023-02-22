# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'aws-sdk-dynamodb'
require 'aws-sdk-sns'
require 'aws-sdk-s3'
require 'httparty'

require 'dmp_finder'
require 'messages'
require 'provenance_finder'
require 'responder'
require 'ssm_reader'

module Functions
  # The handler for POST /dmps/validate
  class PdfDownloader
    SOURCE = 'SNS Topic - Download'

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
    #             "download": "https://example.com/api/dmps/12345.pdf"
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
        location = json.fetch('dmproadmap_links', {})['download']

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp "EVENT: #{event}" if debug
        pp "CONTEXT: #{context.inspect}" if debug

        if provenance_pk.nil? || dmp_pk.nil? || location.nil?
          p "#{Messages::MSG_INVALID_ARGS} - prov: #{provenance_pk}, dmp: #{dmp_pk}, location: #{location}"
          return Responder.respond(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
        end

        table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))

        # Load the Provenance info
        p_finder = ProvenanceFinder.new(client: client, table_name: table, debug_mode: debug)
        resp = p_finder.provenance_from_pk(p_key: provenance_pk)
        provenance = resp[:items].first if resp[:status] == 200

        # Load the DMP metadata
        dmp = load_dmp(provenance: provenance, dmp_pk: dmp_pk, table: table, client: client, debug: debug)
        if dmp.nil?
          p "#{Messages::MSG_DMP_NOT_FOUND} - #{dmp_pk}"
          return Responder.respond(status: 404, errors: Messages::MSG_DMP_NOT_FOUND,
                                   event: event)
        end

        # Fetch the DMP document
        payload = download_dmp(provenance: provenance, location: location, debug: debug)
        if payload.nil?
          return Responder.respond(status: 500, errors: Messages::MSG_DOWNLOAD_FAILURE,
                                   event: event)
        end

        # Store the document in S3 Bucket and record the access URL in the DMP metadata
        object_key = save_document(document: payload, dmp_pk: dmp_pk)
        return Responder.respond(status: 500, errors: Messages::MSG_S3_FAILURE, event: event) if object_key.nil?

        # Record the object_key on the DMP record
        resp = update_document_url(table: table, dmp: dmp, original_uri: location,
                                   object_key: object_key, debug: debug)
        return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event) unless resp

        Responder.respond(status: 200, errors: Messages::MSG_SUCCESS, event: event)
      rescue JSON::ParserError
        p "#{Messages::MSG_INVALID_JSON} - MESSAGE: #{msg}"
        Responder.respond(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        p "FATAL -- DMP ID: #{dmp_pk}, MESSAGE: #{e.message}"
        p e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Fetch the DMP JSON from the DyanamoDB Table
      # --------------------------------------------------------------------------------
      def load_dmp(provenance:, dmp_pk:, table:, client:, debug: false)
        return nil if table.nil? || client.nil? || provenance.nil? || dmp_pk.nil?

        # Fetch the DMP
        dmp_finder = DmpFinder.new(provenance: provenance, table_name: table, client: client, debug_mode: debug)
        response = dmp_finder.find_dmp_by_pk(p_key: dmp_pk, s_key: KeyHelper::DMP_LATEST_VERSION)
        response[:status] == 200 ? response[:items].first['dmp'] : nil
      end

      # Validate the URI and tthen download the document
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def download_dmp(provenance:, location:, debug: false)
        return nil if provenance.nil? || location.nil?

        # Verify that the location is a valid URL and it is owned by the Provenance!
        uri = URI(location.to_s)
        if provenance.nil? || provenance['downloadUri'].nil? || !uri.to_s.start_with?(provenance['downloadUri'])
          p "Invalid download location, #{uri} for '#{provenance['PK']}' expecting: #{provenance['downloadUri']}"
          return nil
        end

        headers = { 'User-Agent': 'DMPHub (dmphub.cdlib.org)' }
        headers = headers.merge(authenticate(provenance: provenance, debug: debug))

        opts = { headers: headers, follow_redirects: true, limit: 6, timeout: 60 }
        opts[:debug_output] = Logger.new($stdout) if debug

        resp = HTTParty.get(uri.to_s, opts)
        unless [200].include?(resp.code)
          p "#{Messages::MSG_DOWNLOAD_FAILURE} - status: #{resp.code} - body #{resp.body}"

          # TODO: move this retry logic out of the function and set it up in the queue logic
          # If we got a Proxy error, sleep for 10 seconds and then try again
          if resp.code == 502
            sleep(10)
            return download_dmp(provenance: provenance, location: location, debug: debug)
          end
          return nil
        end
        resp.body
      rescue URI::Error => e
        p "DMP ID: #{dmp_pk} - Bad download location, not a valid URI: '#{location}' - #{e.message}"
        nil
      end
      # rubocop:enable Metrics/AbcSize

      # Save the DMP document in the S3 bucket
      # --------------------------------------------------------------------------------
      def save_document(document:, dmp_pk:)
        return nil if document.to_s.strip.empty? || dmp_pk.nil? || ENV['S3_BUCKET'].nil?

        # CloudFront S3 bucket is in the Global us-east-1 region!
        s3_client = Aws::S3::Client.new(region: ENV['AWS_REGION'])
        key = "dmps/#{SecureRandom.hex(8)}.pdf"
        resp = s3_client.put_object({
                                      body: document,
                                      bucket: ENV['S3_BUCKET'].gsub('arn:aws:s3:::', ''),
                                      key: key,
                                      tagging: "DMP_ID=#{CGI.escape(KeyHelper.remove_pk_prefix(dmp: dmp_pk))}"
                                    })
        resp.successful? ? key : nil
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: SOURCE, message: "S3: DMP ID: #{dmp_pk}, MESSAGE: #{e.message}",
                            details: e.backtrace)
        nil
      end

      # Update the DMP record with the location of the downloaded document
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def update_document_url(table:, dmp:, original_uri:, object_key:, debug: false)
        return false unless dmp.is_a?(Hash) && !table.nil? && !original_uri.nil? && !object_key.nil?

        # Doing a direct update of the record here since we don't want it to version
        ids = dmp['dmproadmap_related_identifiers'].reject do |id|
          id['work_type'] == 'output_management_plan' && id['descriptor'] == 'is_metadata_for'
        end
        ids << JSON.parse({
          type: 'url', work_type: 'output_management_plan', descriptor: 'is_metadata_for',
          identifier: "#{SsmReader.get_ssm_value(key: SsmReader::S3_BUCKET_URL)}/#{object_key}"
        }.to_json)
        dmp['dmproadmap_related_identifiers'] = ids
        dmp['dmphub_provenance_download_url'] = original_uri if dmp['dmphub_provenance_download_url'].nil?

        dynamodb_client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
        resp = dynamodb_client.put_item({ table_name: table, item: dmp,
                                          return_consumed_capacity: debug ? 'TOTAL' : 'NONE' })
        resp.successful?
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: SOURCE, message: "Dynamo update: MESSAGE: #{e.message}",
                            details: ([dmp] << e.backtrace).flatten.compact)
        false
      end
      # rubocop:enable Metrics/AbcSize

      # Attempt to authenticate and retrieve an access token from the Provenance's tokenUri
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def authenticate(provenance:, debug: false)
        return {} if provenance.nil? || provenance['tokenUri'].nil?

        provenance_name = KeyHelper.remove_pk_prefix(provenance: provenance['PK'])
        client_id = SsmReader.get_ssm_value(key: SsmReader::PROVENANCE_API_CLIENT_ID,
                                            provenance_name: provenance_name)
        client_secret = SsmReader.get_ssm_value(key: SsmReader::PROVENANCE_API_CLIENT_SECRET,
                                                provenance_name: provenance_name)
        return {} if client_id.nil? || client_secret.nil?

        payload = "grant_type=client_credentials&client_id=#{client_id}&client_secret=#{client_secret}"
        resp = HTTParty.post(provenance['tokenUri'], { headers: { Accept: 'application/json' },
                                                       body: payload,
                                                       follow_redirects: true, limit: 5, debug: debug })
        return {} unless resp.code == 200

        json = JSON.parse(resp.body)
        { Authorization: "#{json.fetch('token_type', 'Bearer')} #{json['access_token']}" }
      rescue JSON::ParserError
        msg = "Unable to authenticate. Invalid response from '#{provenance['tokenUri']}'."
        Responder.log_error(source: SOURCE, message: msg, details: [resp.inspect])
        {}
      rescue StandardError => e
        p "PdfDownloader: Unable to authenticate at #{provenance['tokenUri']} - #{e.message}"
        {}
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    end
  end
end
