# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-citation'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-id'

module Functions
  # Lambda function that is invoked by SNS and communicates with EZID to register/update DMP IDs
  class Citer
    SOURCE = 'Citer'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "DMP change",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "PK": "DMP#doi.org/10.12345/ABC123",
    #           "SK": "VERSION#latest",
    #           "dmproadmap_related_identifier": {
    #             "work_type": "article",
    #             "descriptor": "references",
    #             "type": "doi",
    #             "identifier": "https://dx.doi.org/10.12345/ABCD1234"
    #           }
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def process(event:, context:)
        # Setup the Logger
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.aws_request_id if context.is_a?(LambdaContext)
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # No need to validate the source and detail-type because that is done by the EventRule
        detail = event.fetch('detail', {})
        json = detail.is_a?(Hash) ? detail : JSON.parse(detail)
        dmp_pk = json['PK']
        dmp_sk = json.fetch('SK', Uc3DmpId::Helper::DMP_LATEST_VERSION)

        if !dmp_pk.nil? && !dmp_sk.nil?
          # Load the DMP metadata
          dmp = Uc3DmpId::Finder.by_pk(p_key: dmp_pk, s_key: dmp_sk, cleanse: false, logger:)
          unless dmp.nil?
            # Get all of the related identifiers that are DOIs and are un-cited
            identifiers = dmp.fetch('dmp', {}).fetch('dmproadmap_related_identifiers', [])
            uncited = Uc3DmpId::Helper.citable_related_identifiers(dmp: dmp['dmp'])

            if identifiers.any? && uncited.any?
              existing_citations = identifiers.reject { |id| uncited.include?(id) }
              processed = []
              # rubocop:disable Metrics/BlockNesting
              uncited.each do |identifier|
                citation = Uc3DmpCitation::Citer.fetch_citation(doi: identifier['identifier']&.strip, logger:)
                identifier['citation'] = citation unless citation.nil?
                processed << identifier
              end
              # rubocop:enable Metrics/BlockNesting

              logger.debug(message: 'Results of citation retrieval', details: processed)
              dmp['dmp']['dmproadmap_related_identifiers'] = existing_citations + processed

              # Remove the version info because we don't want to save it on the record
              dmp['dmp'].delete('dmphub_versions')

              client = Uc3DmpDynamo::Client.new
              client.put_item(json: dmp['dmp'], logger:)
            end
          end
        end
      rescue Uc3DmpId::FinderError => e
        logger.error(message: "Finder error: #{e.message}", details: e.backtrace)
      rescue Uc3DmpCitation::CiterError => e
        logger.error(message: "Citer error: #{e.message}", details: e.backtrace)
      rescue Uc3DmpExternalApi::ExternalApiError => e
        logger.error(message: "External API error: #{e.message}", details: e.backtrace)
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: "Fatal error - #{e.message}", event_details: json }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status:, items:, errors:, event:,
          page: params['page'], per_page: params['per_page']
        )
      end
    end
  end
end
