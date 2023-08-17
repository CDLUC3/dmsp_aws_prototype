# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'bibtex'
require 'citeproc'
require 'csl/styles'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-external-api'
require 'uc3-dmp-id'

module Functions
  # Lambda function that is invoked by SNS and communicates with EZID to register/update DMP IDs
  class Citer
    SOURCE = 'Citer'

    APPLICATION_NAME = 'DMPTool'
    DEFAULT_CITATION_STYLE = 'chicago-author-date'
    DEFAULT_DOI_URL = 'http://doi.org'
    DEFAULT_WORK_TYPE = 'Dataset'

    MSG_BIBTEX_FAILURE = 'Unable to fetch Bibtex for the specified DOI.'
    MSG_UNABLE_TO_UPDATE = 'Unable to update the citations on the DMP ID.'

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
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

        # No need to validate the source and detail-type because that is done by the EventRule
        detail = event.fetch('detail', {})
        json = detail.is_a?(Hash) ? detail : JSON.parse(detail)
        dmp_pk = json['PK']
        dmp_sk = json.fetch('SK', Uc3DmpId::Helper::DMP_LATEST_VERSION)

        if !dmp_pk.nil? && !dmp_sk.nil?
          # Load the DMP metadata
          dmp = Uc3DmpId::Finder.by_pk(p_key: dmp_pk, s_key: dmp_sk, cleanse: false, logger: logger)
          if !dmp.nil?
            # Get all of the related identifiers that are DOIs and are un-cited
            identifiers = dmp.fetch('dmp', {}).fetch('dmproadmap_related_identifiers', [])
            uncited = Uc3DmpId::Helper.citable_related_identifiers(dmp: dmp['dmp'])

            if identifiers.any? && uncited.any?
              existing_citations = identifiers.reject { |id| uncited.include?(id) }
              headers = { Accept: 'application/x-bibtex' }

              processed = []
              uncited.each do |identifier|
                uri = _doi_to_uri(doi: identifier['identifier']&.strip)
                if !uri.nil? && !uri.blank?
                  logger.debug(message: "Fetching BibTeX from: #{uri}")
                  resp = Uc3DmpExternalApi::Client.call(url: uri, method: :get, additional_headers: headers, logger: logger)

                  unless resp.nil? || resp.to_s.strip.empty?
                    bibtex = BibTeX.parse(_cleanse_bibtex(text: resp))
                    work_type = identifier['work_type'].nil? ? determine_work_type(bibtex: bibtex) :  identifier['work_type']
                    identifier['citation'] = _bibtex_to_citation(uri: uri, work_type: work_type, bibtex: bibtex)
                  end
                end

                processed << identifier
              end

              logger.debug(message: 'Results of citation retrieval', details: processed)
              dmp['dmp']['dmproadmap_related_identifiers'] = existing_citations + processed

              # Remove the version info because we don't want to save it on the record
              dmp['dmp'].delete('dmphub_versions')

              client = Uc3DmpDynamo::Client.new
              resp = client.put_item(json: dmp['dmp'], logger: logger)
            end
          end
        end
      rescue Uc3DmpId::FinderError => e
        logger.error(message: e.message, details: e.backtrace)
      rescue Uc3DmpExternalApi::ExternalApiError => e
        logger.error(message: e.message, details: e.backtrace)
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: "Fatal error - #{e.message}", event_details: json}
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event: event)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status: status, items: items, errors: errors, event: event,
          page: params['page'], per_page: params['per_page']
        )
      end

      # Will convert 'doi:10.1234/abcdefg' to 'http://doi.org/10.1234/abcdefg'
      def _doi_to_uri(doi:)
        val = doi.match(Uc3DmpId::Helper::DOI_REGEX).to_s
        return nil if val.nil? || val.strip == ''

        doi.start_with?('http') ? doi : "#{DEFAULT_DOI_URL}/#{doi.gsub('doi:', '')}"
      end

      # If no :work_type was specified we can try to derive it from the BibTeX metadata
      def _determine_work_type(bibtex:)
        return '' if bibtex.nil? || bibtex.data.nil? || bibtex.data.first.nil?

        return 'article' unless bibtex.data.first.journal.nil?

        ''
      end

      def _cleanse_bibtex(text:)
        return nil if text.nil? || text.to_s.strip == ''

        # Make sure we're working with UTF8
        utf8 = text.force_encoding('UTF-8')

        # Remove any encoded HTML (e.g. "Regular text $\\lt$strong$\\gt$Bold text$\\lt$/strong$\\gt$")
        utf8 = utf8.gsub(%r{\$?\\\$?(less|lt|Lt)\$/?[a-zA-Z]+\$?\\\$?(greater|gt|Gt)\$}, '')
        # Replace any special dash, semicolon and quote characters with a minus sign or single/double quote
        utf8 = utf8.gsub(%r{\$?\\(T|t)ext[a-zA-Z]+dash\$?}, '-').gsub(%r{\{(T|t)ext[a-zA-Z]+dash\}}, '-')
                   .gsub(%r{\$?\\(M|m)athsemicolon\$?}, ':').gsub(%r{\{(M|m)semicolon\}}, ':')
                   .gsub(%r{\$?\\(T|t)extquotesingle\$?}, "'").gsub(%r{\{(T|t)extquotesingle\}}, "'")
                   .gsub(%r{\$?\\(T|t)extquotedouble\$?}, '"').gsub(%r{\{(T|t)extquotedouble\}}, '"')
        # Remove any remaining `\v` entries which attempt to construct an accented character
        utf8.gsub(%r{\\v}, '')
      end

      # Convert the BibTeX item to a citation
      def _bibtex_to_citation(uri:, work_type: DEFAULT_WORK_TYPE, bibtex:, style: DEFAULT_CITATION_STYLE)
        return nil unless uri.is_a?(String) && uri.strip != ''
        return nil if bibtex.nil? || bibtex.data.nil? || bibtex.data.first.nil?

        cp = CiteProc::Processor.new(style: style, format: 'html')
        cp.import(bibtex.to_citeproc)
        citation = cp.render(:bibliography, id: bibtex.data.first.id)
        return nil unless citation.is_a?(Array) && citation.any?

        # The CiteProc renderer has trouble with some things so fix them here
        #   - For some reason words in all caps in the title get wrapped in curl brackets
        citation = citation.first.gsub('{', '').gsub('}', '')

        unless work_type.nil? || work_type.strip == ''
          # This supports the :apa and :chicago-author-date styles
          citation = citation.gsub(/\.”\s+/, "\.” [#{work_type.gsub('_', ' ').capitalize}]. ")
                             .gsub(/<\/i>\.\s+/, "<\/i>\. [#{work_type.gsub('_', ' ').capitalize}]. ")
        end

        # Convert the URL into a link. Ensure that the trailing period is not a part of
        # the link!
        citation.gsub(URI.regexp) do |url|
          if url.start_with?('http')
            '<a href="%{url}" target="_blank">%{url}</a>.' % {
              url: url.end_with?('.') ? uri : "#{uri}."
            }
          else
            url
          end
        end
      end
    end
  end
end
