# rubocop:disable Naming/FileName
# frozen_string_literal: true

require 'bibtex'
require 'citeproc'
require 'csl/styles'

require 'uc3-dmp-external-api'

module Uc3DmpCitation
  class CiterError < StandardError; end

  # Clas that fetches Citations for a given DOI
  class Citer
    DEFAULT_CITATION_STYLE = 'chicago-author-date'
    DEFAULT_DOI_URL = 'http://doi.org'
    DEFAULT_WORK_TYPE = 'Dataset'

    DOI_REGEX = %r{[0-9]{2}\.[0-9]{4,}/[a-zA-Z0-9/_.-]+}

    MSG_BIBTEX_FAILURE = 'Unable to fetch Bibtex for the specified DOI.'
    MSG_UNABLE_TO_UPDATE = 'Unable to update the citations on the DMP ID.'

    class << self
      # rubocop:disable Metrics/AbcSize
      def fetch_citation(doi:, work_type: DEFAULT_WORK_TYPE, style: DEFAULT_CITATION_STYLE, logger: nil)
        uri = _doi_to_uri(doi:)
        return nil if uri.nil? || uri.blank?

        headers = { Accept: 'application/x-bibtex' }
        logger.debug(message: "Fetching BibTeX from: #{uri}") if logger.respond_to?(:debug)
        resp = Uc3DmpExternalApi::Client.call(url: uri, method: :get, additional_headers: headers, logger:)
        return nil if resp.nil? || resp.to_s.strip.empty?

        bibtex_to_citation(bibtex_as_string: resp)
      end
      # rubocop:enable Metrics/AbcSize

      # Convert the specified BibTex string into a citation
      def bibtex_to_citation(uri:, bibtex_as_string:)
        return nil unless bibtex_as_string.is_a?(String) && uri.is_a?(String)

        bibtex = BibTeX.parse(_cleanse_bibtex(text: bibtex_as_string))
        work_type = work_type.nil? ? _determine_work_type(bibtex:) : work_type
        style = DEFAULT_CITATION_STYLE if style.nil?
        _bibtex_to_citation(uri:, work_type:, style:, bibtex:)
      end

      private

      # Will convert 'doi:10.1234/abcdefg' to 'http://doi.org/10.1234/abcdefg'
      def _doi_to_uri(doi:)
        val = doi.match(DOI_REGEX).to_s
        return nil if val.nil? || val.strip == ''

        doi.start_with?('http') ? doi : "#{DEFAULT_DOI_URL}/#{doi.gsub('doi:', '')}"
      end

      # If no :work_type was specified we can try to derive it from the BibTeX metadata
      def _determine_work_type(bibtex:)
        return '' if bibtex.nil? || bibtex.data.nil? || bibtex.data.first.nil?

        return 'article' unless bibtex.data.first.respond_to?(:journal) || bibtex.data.first.journal.nil?

        ''
      end

      def _cleanse_bibtex(text:)
        return nil if text.nil? || text.to_s.strip == ''

        # Make sure we're working with UTF8
        utf8 = text.force_encoding('UTF-8')

        # Remove any encoded HTML (e.g. "Regular text $\\lt$strong$\\gt$Bold text$\\lt$/strong$\\gt$")
        utf8 = utf8.gsub(%r{\$?\\\$?(less|lt|Lt)\$/?[a-zA-Z]+\$?\\\$?(greater|gt|Gt)\$}, '')
        # Replace any special dash, semicolon and quote characters with a minus sign or single/double quote
        utf8 = utf8.gsub(/\$?\\(T|t)ext[a-zA-Z]+dash\$?/, '-').gsub(/\{(T|t)ext[a-zA-Z]+dash\}/, '-')
                   .gsub(/\$?\\(M|m)athsemicolon\$?/, ':').gsub(/\{(M|m)semicolon\}/, ':')
                   .gsub(/\$?\\(T|t)extquotesingle\$?/, "'").gsub(/\{(T|t)extquotesingle\}/, "'")
                   .gsub(/\$?\\(T|t)extquotedouble\$?/, '"').gsub(/\{(T|t)extquotedouble\}/, '"')
        # Remove any remaining `\v` entries which attempt to construct an accented character
        utf8.gsub(/\\v/, '')
      end

      # Convert the BibTeX item to a citation
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def _bibtex_to_citation(uri:, bibtex:, work_type: DEFAULT_WORK_TYPE, style: DEFAULT_CITATION_STYLE)
        return nil unless uri.is_a?(String) && uri.strip != ''
        return nil if bibtex.nil? || bibtex.data.nil? || bibtex.data.first.nil?

        cp = CiteProc::Processor.new(style:, format: 'html')
        cp.import(bibtex.to_citeproc)
        citation = cp.render(:bibliography, id: bibtex.data.first.id)
        return nil unless citation.is_a?(Array) && citation.any?

        # The CiteProc renderer has trouble with some things so fix them here
        #   - For some reason words in all caps in the title get wrapped in curl brackets
        citation = citation.first.gsub('{', '').gsub('}', '')

        unless work_type.nil? || work_type.strip == ''
          # This supports the :apa and :chicago-author-date styles
          citation = citation.gsub(/\.”\s+/, ".” [#{work_type.gsub('_', ' ').capitalize}]. ")
                             .gsub(%r{</i>\.\s+}, "</i>. [#{work_type.gsub('_', ' ').capitalize}]. ")
        end

        # Convert the URL into a link. Ensure that the trailing period is not a part of
        # the link!
        citation.gsub(URI::DEFAULT_PARSER.make_regexp) do |url|
          if url.start_with?('http')
            format('<a href="%{url}" target="_blank">%{url}</a>.', url: url.end_with?('.') ? uri : "#{uri}.")
          else
            url
          end
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
# rubocop:enable Naming/FileName
