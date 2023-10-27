# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'text'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-external-api'
require 'uc3-dmp-id'

module Functions
  # A service that queries DataCite EventData
  class AugmenterDatacite
    SOURCE = 'DataCite Augmenter'

    GRAPHQL_ENDPOINT = 'https://api.datacite.org/graphql'
    GRAPHQL_TIMEOUT_SECONDS = 30

    GRAPHQL_FAILURE = 'Unable to query the DataCite GraphQL API at this time.'

    MSG_EMPTY_RESPONSE = 'DatCite did not return any results.'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "RelatedWorkScan",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "dmp_pk": "DMP#doi.org/10.12345/ABC123",
    #           "augmenter": "AUGMENTERS#datacite",
    #           "run_id": "2023-10-16_ABCD1234"
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        # No need to validate the source and detail-type because that is done by the EventRule
        details = _process_input(detail: event.fetch('detail', {}))

        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : details[:run_id]
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)
        logger&.debug(message: 'Augmenting DMP:', details:)

        unless details[:dmp_pk].nil? || details[:augmenter_pk].nil? || details[:run_id].nil?
          client = Uc3DmpDynamo::Client.new
          augmenter = _fetch_augmenter(client:, id: details[:augmenter_pk], logger:)
          dmp = Uc3DmpId::Finder.by_pk(client:, p_key: details[:dmp_pk], cleanse: false, logger:)

          if dmp.is_a?(Hash) && !augmenter.nil?
            dmp = dmp['dmp'] unless dmp['dmp'].nil?
            comparator = Uc3DmpId::Comparator.new(dmp:, logger:)
            logger&.debug(message: 'Working with the following DMP details:', details: comparator.details_hash)

            # Figure out what years to search
            years = _search_years(dmp:)
            logger&.debug(message: 'Scanning DataCite for the following years:', details: years)
            # Search for related works by the Funder
            related_works = _process_funders(years:, comparator:, logger:)

            # Search for related works by the Researchers ORCIDs or their Affiliation RORs

            _augment_dmp(run_id: details[:run_id], augmenter:, dmp:, related_works:) if related_works.any?
          end
        else
          logger&.error(message: 'Missing event detail!', details:)
        end
      rescue Uc3DmpId::FinderError => e
        logger.error(message: "Finder error: #{e.message}", details: e.backtrace)
      rescue Uc3DmpExternalApi::ExternalApiError => e
        logger.error(message: "External API error: #{e.message}", details: e.backtrace)
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: "Fatal error - #{e.message}", event_details: dmp }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      end

      private

      # Process the incoming Event detail
      def _process_input(detail:)
        json = detail.is_a?(Hash) ? detail : JSON.parse(detail)
        {
          dmp_pk: json['dmp_pk'],
          augmenter_pk: json['augmenter'],
          run_id: json['run_id']
        }
      end

      # Load the Augmenter record from Dynamo
      def _fetch_augmenter(client:, id:, logger:)
        client = Uc3DmpDynamo::Client.new if client.nil?
        client.get_item(key: { PK: id, SK: 'PROFILE' }, logger:)
      end

      # Search DataCite for the researcher
      def process_person_id(run_id:, augmenter:, id:, dmp:, logger:)
        return dmp unless id['type'].to_s.downcase.strip == 'orcid' && !id['identifier'].nil?

        orcid = id['identifier'].to_s.downcase.strip.gsub(ORCID_PREFIX_REGEX, ORCID_PREFIX)
        body = graphql_researcher(orcid:)
        resp = Uc3DmpExternalApi::Client.call(url: GRAPHQL_ENDPOINT, method: :post, body: body, logger:)
        logger&.debug(message: "GraphQl results for ORCID: #{orcid}", details: resp.inspect)
        logger&.error(message: MSG_EMPTY_RESPONSE, details: resp) if resp.nil? || resp.to_s.strip.empty?
        return dmp if resp.nil? || resp.to_s.strip.empty?

        dmp = process_results(run_id:, augmenter:, orcid:, dmp:, logger:)
      end

      # Search DataCite for the funder affiliation
      def _process_funders(years:, comparator:, logger:)
        results = []
        return results if comparator&.details_hash&.fetch(:funder_ids, []).empty? || years.empty?

        # Call the API for each year within the range
        years.each do |year|
          comparator.details_hash[:funder_ids].each do |funder_id|
            resp = _call_datacite(body: _graphql_funder(fundref: funder_id, year: year), logger:)
            data = resp.is_a?(Hash) ? resp['data'] : JSON.parse(resp)

            results << _select_relevant_content(data: data.fetch('funder', {}), comparator:, logger:)

p "RELATED WORKS FROM #{funder_id} for #{year}:"
p results

          end
        end

        results.any? ? results.flatten.compact.uniq : results
      end

      # Check the DataCite results to see if we should make any updates to the DMP
      def _augment_dmp(run_id:, augmenter:, dmp:, related_works:)

      end

      # Extract any items within our date range
      def _select_relevant_content(data:, comparator:, logger:)
        ret = { publications: [], datasets: [], softwares: [] }
        data.fetch('publications', {}).fetch('nodes', []).each do |publication|
          result = _compare_result(comparator:, hash: publication)
          next if result.nil?

          ret[:publications] << result
        end

        data.fetch('datasets', {}).fetch('nodes', []).each do |dataset|
          result = _compare_result(comparator:, hash: dataset)
          next if result.nil?

          ret[:datasets] << result
        end
        data.fetch('softwares', {}).fetch('nodes', []).each do |software|
          result = _compare_result(comparator:, hash: software)
          next if result.nil?

          ret[:softwares] << result
        end
        ret
      end

      # Compare the work to the DMP
      def _compare_result(comparator:, hash:)
        details_hash = _extract_comparable(hash: hash)
        return nil unless details_hash.is_a?(Hash) && !details_hash['title'].nil?

        result = comparator.compare(hash: pub_hash)
        return nil if result[:score] <= 0

        result[:source] = ['Datatcite', hash.fetch('publisher', hash.fetch('member', {})['name'])].join(' - ')
        result.merge({ work: hash })
      rescue Uc3DmpId::ComparatorError => e
        logger.error(message: "Comparator error: #{e.message}", details: e.backtrace)
        nil
      end

      # Determine what years we want to query for
      def _search_years(dmp:)
        current_year = Time.now.strftime('%Y').to_i
        creation = Time.parse(dmp['created']).strftime('%Y').to_i
        project = dmp.fetch('project', []).sort { |a, b| [b['end'], b['start']] <=> [a['end'], a['start']] }.first
        proj_start = Time.parse(project['start']).strftime('%Y').to_i unless project['start'].nil?
        proj_end = Time.parse(project['end']).strftime('%Y').to_i unless project['end'].nil?

        # If the Project start year was nil, invent one based on the Project end year or the DMP ID creation date
        proj_start = proj_end.nil? ? creation : proj_end - 1 if proj_start.nil?
        proj_end = proj_start + 1 if proj_end.nil?
        # Return an empty array if the start year is greater than the current year
        return [] if proj_start > current_year
        # Return the single year if the project start and end years match
        return [proj_start] if proj_start == proj_end

        # We don't want to query beyond the current year, so cap the end year to the current year
        proj_end = proj_end + 1 > current_year ? current_year : proj_end + 1
        # Cap the start year to 3 years prior to the project end
        proj_start = proj_end - 3 if proj_end - proj_start > 3
        (proj_start..proj_end).map { |idx| idx.to_s }
      end

      # Call DataCite
      def _call_datacite(body:, logger:)
        payload = nil
        cntr = 0
        while cntr <= 2
          begin
            resp = Uc3DmpExternalApi::Client.call(url: GRAPHQL_ENDPOINT, method: :post, body: body, logger:)

            logger&.info(message: MSG_EMPTY_RESPONSE, details: resp) if resp.nil? || resp.to_s.strip.empty?
            payload = resp unless resp.nil? || resp.to_s.strip.empty?
            cntr = 3 unless payload.nil?
          rescue Net::ReadTimeout
            logger&.info(message: 'Httparty timeout', details: body)
            sleep(3)
          end

          cntr += 1
        end
        payload
      end

      # Convert the DataCite :work into a hash for the Uc3DmpId::Comparator.
      # It is expecting:
      #  {
      #    title: "Example research project",
      #    abstract: "Lorem ipsum psuedo abstract",
      #    keywords: ["foo", "bar"],z
      #    people: [
      #      {
      #        id: "https://orcid.org/blah",
      #        last_name: "doe",
      #        affiliation: { id: "https://ror.org/blah", name: "Foo" }
      #      }
      #    ],
      #    fundings: [
      #      { id: "https://doi.org/crossref123", name: "Bar", grant: ["1234", "http://foo.bar/543"] }
      #    ],
      #    repositories: [
      #      { id: ["http://some.repo.org", "https://doi.org/re3data123"], name: "Repo" }
      #    ]
      #  }
      def _extract_comparable(hash:)
        return nil unless hash.is_a?(Hash)

        keywords = hash.fetch('subjects', []).map { |entry| entry['subject'] }
        keywords << hash.fetch('fieldsOfScience', []).map { |entry| entry['name'] }
        people = hash.fetch('creators', []).map { |entry| _extract_person(hash: entry) }
        people << hash.fetch('contributors', []).map { |entry| _extract_person(hash: entry) }
        fundings = hash.fetch('fundingReferences', []).map { |entry| _extract_funding(hash: entry) }
        repo = hash.fetch('repository', {})
        repository = { name: repo['name'] } unless repo.nil?
        repository[:id] = [repo['url'], repo['re3dataUrl']]&.flatten&.compact&.uniq unless repo.nil?

        JSON.parse({
          title: hash.fetch('titles', []).map { |entry| entry['title'] }.join(' '),
          abstract: hash.fetch('descriptions', []).map { |entry| entry['description'] }.join(' '),
          keywords: keywords&.flatten&.compact&.uniq,
          people: people&.flatten&.compact&.uniq,
          fundings: fundings,
          repositories: [repository]
        }.to_json)
      end

      # Convert the incoming DataCite entry for the person into the hash for the Uc3DmpId::Comparator
      def _extract_person(hash:)
        name = hash['familyName']
        name = hash['name'].include?(', ') ? hash['name'].split(', ').first : hash['name'].split.last if name.nil?
        {
          id: hash['id'],
          last_name: name,
          affiliation: hash['affiliation']
        }
      end

       # Convert the incoming DataCite entry for the person into the hash for the Uc3DmpId::Comparator
       def _extract_funding(hash:)
        grants = [hash['awardUri']&.downcase&.strip, hash['awardNumber']&.downcase&.strip]
        {
          id: hash['funderIdentifier'],
          last_name: hash['funderName'],
          grant: grants&.flatten&.compact&.uniq
        }
      end

      # Search the Pid graph by Funder Id
      def _graphql_funder(fundref:, year:)
        {
          variables: { fundref: fundref, year: year },
          operationName: 'funderQuery',
          query: <<~TEXT
            query funderQuery ($fundref: ID!, $year: String)
            {
              funder(id: $fundref) {
                id
                name
                alternateName
                publications(published: $year) { nodes #{_related_work_fragment} }
                datasets(published: $year) { nodes #{_related_work_fragment} }
                softwares(published: $year) { nodes #{_related_work_fragment} }
              }
            }
          TEXT
        }.to_json
      end

      # Search the Pid Graph by Affiliation ROR
      def _graphql_affiliation(ror:)
        {
          variables: { ror: ror, year: year },
          operationName: 'affiliationQuery',
          query: <<~TEXT
            query affiliationQuery ($ror: ID!, $year: String)
            {
              organization(id: $ror) {
                id
                name
                alternateName
                publications(published: $year) { nodes #{_related_work_fragment} }
                datasets(published: $year) { nodes #{_related_work_fragment} }
                softwares(published: $year) { nodes #{_related_work_fragment} }
              }
            }
          TEXT
        }.to_json
      end

      # Search the Pid Graph by Researcher ORCID
      def _graphql_researcher(orcid:)
        {
          variables: { orcidId: orcid, year: year },
          operationName: 'researcherQuery',
          query: <<~TEXT
            query researcherQuery ($orcidId: ID!, $year: String)
            {
              person(id: $orcidId) {
                id
                name
                publications(published: $year) { nodes #{_related_work_fragment} }
                datasets(published: $year) { nodes #{_related_work_fragment} }
                softwares(published: $year) { nodes #{_related_work_fragment} }
              }
            }
          TEXT
          }.to_json
      end

      def _related_work_fragment
        <<~TEXT
        {
          id
          doi
          type
          titles {
            title
          }
          descriptions {
            description
          }
          creators #{_creator_fragment}
          contributors #{_contributor_fragment}
          fundingReferences #{_funding_fragment}
          publisher
          member {
            name
            rorId
          }
          repository #{_repository_fragment}
          fieldsOfScience #{_basic_fragment}
          subjects {
            subject
          }
          publicationYear
          dates #{_date_fragment}
          registered
          registrationAgency #{_basic_fragment}
          relatedIdentifiers #{_related_identifier_fragment}
          bibtex
        }
        TEXT
      end

      def _creator_fragment
        <<~TEXT
        {
          id
          name
          familyName
          givenName
          affiliation #{_basic_fragment}
        }
        TEXT
      end

      def _contributor_fragment
        <<~TEXT
        {
          id
          contributorType
          name
          familyName
          givenName
          affiliation #{_basic_fragment}
        }
        TEXT
      end

      def _funding_fragment
        <<~TEXT
        {
          funderIdentifier
          funderName
          awardUri
          awardTitle
          awardNumber
        }
        TEXT
      end

      def _repository_fragment
        <<~TEXT
        {
          uid
          name
          url
          description
          re3dataUrl
          re3dataDoi
        }
        TEXT
      end

      def _related_identifier_fragment
        <<~TEXT
        {
          relationType
          resourceTypeGeneral
          relatedIdentifierType
          relatedIdentifier
          relatedMetadataScheme
          schemeType
          schemeUri
        }
        TEXT
      end

      def _date_fragment
        <<~TEXT
        {
          dateType
          date
        }
        TEXT
      end

      def _basic_fragment
        <<~TEXT
        {
          id
          name
        }
        TEXT
      end
    end
  end
end
