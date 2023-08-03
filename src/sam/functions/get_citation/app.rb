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
require 'uc3-dmp-external-api'
require 'uc3-dmp-id'

module Functions
  # A Proxy service that queries the NSF Awards API and transforms the results into a common format
  class CitationFetcher
    SOURCE = 'CitationFetcher'

    DEFAULT_CITATION_STYLE 'chicago-author-date'
    DEFAULT_DOI_URL = 'https://doi.org'

    def self.process(event:, context:)
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      detail = event.fetch('detail', {})
      json = detail.is_a?(Hash) ? detail : JSON.parse(detail)
      provenance_pk = json['dmphub_provenance_id']
      dmp_pk = json['PK']
      _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS], event: event) if provenance_pk.nil? || dmp_pk.nil?

      # Load the DMP metadata
      dmp = Uc3DmpId::Finder.by_pk(p_key: dmp_pk, logger: logger)
      _respond(status: 404, errors: [Uc3DmpId::MSG_DMP_NOT_FOUND], event: event) if dmp.nil?

      works = Helper.deep_copy_dmp(obj: dmp.fetch('dmproadmap_related_identifiers', []))
      updated = false

      works.each do |work|
        # Ignore the link to the PDF narrative for the DMP
        next unless work['citation'].nil? ||
                    (work['descriptor'] == 'is_metadata_for' && work['work_type'] == 'output_management_plan')

        updated = true
        uri = _doi_to_uri(doi: work['identifier'].strip)
        logger.info(message: "Fetching BibTeX from: #{uri}") if logger.respond_to?(:debug)
        resp = Uc3DmpExternalApi::Client.call(url: uri, method: :get, logger: logger)

        if resp.nil? || resp.to_s.strip.empty?
          work['citation'] = "#{uri} No citation available."
        else
          bibtex = BibTeX.parse(resp.body)
          logger.debug(message: "Received BibTeX from: #{uri}", details: resp.body) if logger.respond_to?(:debug)

          work['citation'] = _bibtex_to_citation(
            uri: uri,
            work_type: bibtex?.data?.first?.journal?.nil? ? work['work_type'].humanize : 'article',
            bibtex: bibtex,
            style: DEFAULT_CITATION_STYLE
          )
          logger.debug(message: 'Generated citation:', details: citation) if logger.respond_to?(:debug)
        end
      end
      # Just return if nothing was updated
      _respond(status: 200, items: [], event: event) unless updated

      dmp['dmproadmap_related_identifiers'] = works
      # Save the changes
      client = Uc3DmpDynamo::Client.new
      resp = client.put_item(json: version, logger: logger)
      raise UpdaterError, MSG_DMP_UNABLE_TO_VERSION if resp.nil?

      # Return the new version record
      logger.info(message: "Updated DMP ID: #{dmp['dmp_id']}") if logger.respond_to?(:debug)
      _respond(status: 200, items: [], event: event)
    rescue Uc3DmpId::FinderError => e
      logger.error(message: e.message, details: e.backtrace)
      _respond(status: 500, errors: [e.message], event: event)
    rescue Uc3DmpExternalApi::ExternalApiError => e
      _respond(status: 500, errors: [e.message], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

    private

    # Will convert 'doi:10.1234/abcdefg' to 'http://doi.org/10.1234/abcdefg'
    def _doi_to_uri(doi:)
      return nil unless doi.is_a?(String) && doi.strip != ''

      doi.start_with?('http') ? doi : "#{DEFAULT_DOI_URL}/#{doi.gsub('doi:', '')}"
    end

    # Convert the BibTeX item to a citation
    def _bibtex_to_citation(uri:, work_type:, bibtex:, style:)
      return nil unless uri.is_a?(String) && uri.strip != ''
      return nil if bibtex.nil? || bibtex.data.nil? || bibtex.data.first.nil?

      cp = CiteProc::Processor.new(style: style, format: 'html')
      cp.import(bibtex.to_citeproc)
      citation = cp.render(:bibliography, id: bibtex.data.first.id)
      return nil unless citation.is_a?(Array) && citation.any?

      # The CiteProc renderer has trouble with some things so fix them here
      #
      #   - It has a '{textendash}' sometimes because it cannot render the correct char
      #   - For some reason words in all caps in the title get wrapped in curl brackets
      #   - We want to add the work type after the title. e.g. `[Dataset].`
      #
      citation = citation.first.gsub(/{\\Textendash}/i, '-')
                                .gsub('{', '').gsub('}', '')

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

    # Send the output to the Responder
    def _respond(status:, items: [], errors: [], event: {}, params: {})
      Uc3DmpApiCore::Responder.respond(
        status: status, items: items, errors: errors, event: event,
        page: params['page'], per_page: params['per_page']
      )
    end
  end
end
