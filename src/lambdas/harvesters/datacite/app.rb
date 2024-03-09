# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'date'
require 'text'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-external-api'

module Functions
  # A service that queries DataCite GraphQL API
  class DataCiteHarvester
    SOURCE = 'DataCite Harvester'

    GRAPHQL_ENDPOINT = 'https://api.datacite.org/graphql'
    GRAPHQL_TIMEOUT_SECONDS = 120

    MSG_GRAPHQL_FAILURE = 'Unable to query the DataCite GraphQL API at this time.'
    MSG_EMPTY_RESPONSE = 'DataCite did not return any results.'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "Harvest",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "ror": "https://ror.org/12345",
    #           "dmps": [
    #             {
    #               "people": [
    #                 "john doe",
    #                 "jdoe@example.com"
    #               ],
    #               "people_ids": [
    #                 "https://orcid.org/0000-0000-0000-0000"
    #               ],
    #               "affiliations": [
    #                 "california digital library (cdlib.org)"
    #               ],
    #               "affiliation_ids": [
    #                 "https://ror.org/03yrm5c26"
    #               ],
    #               "funder_ids": [
    #                 "https://ror.org/12345"
    #               ],
    #               "funders": [
    #                 "Example Funder (example.gov)"
    #               ],
    #               "funder_opportunity_ids": [
    #                 "ABC123"
    #               ],
    #               "grant_ids": [
    #                 "1234567890"
    #               ],
    #               "funding_status": "granted",
    #               "dmp_id": "https://dmphub.uc3dev.cdlib.net/dmps/10.12345/A1b2C3",
    #               "title": "my super awesome dmp",
    #               "visibility": "public",
    #               "featured": 1,
    #               "description": "<p>a really interesting project!</p>",
    #               "project_start": "2015-05-12",
    #               "project_end": "2025-08-25",
    #               "created": "2021-11-08",
    #               "modified": "2023-08-25",
    #               "registered": "2021-11-08",
    #               "narrative_url": "https://dmphub.uc3dev.cdlib.net/narratives/af9d7b9533519785.pdf"
    #             }
    #           ]
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        # No need to validate the source and detail-type because that is done by the EventRule
        details = event.fetch('detail', {})
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : nil
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # return if there are no :dmps or no :ror in the details

        # Establish the OpenSearch and Dynamo clients
        dynamo_client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        table = ENV['DYNAMO_TABLE']

        ror = details['ror']
        # Find the start and end dates for our DataCite search
        start_at = _find_start_date(entries: details['dmps'])
        end_at = Date.today.to_s
        range = "#{start_at} TO #{end_at}"

        # Query DataCite
        query = _graphql_affiliation(ror:, range:)
        logger&.debug(message: 'Querying DataCite:', details: query)
        datacite_recs = _query_datacite(query:, logger:)

        # See if the returned DataCite info has any matches to our DMSPs
        resp = _select_relevant_content(datacite_recs:, dmps: details['dmps'], logger:)

        # Update the relevant DMSPs

      rescue Uc3DmpExternalApi::ExternalApiError => e
        logger.error(message: "External API error: #{e.message}", details: e.backtrace)
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: "Fatal error - #{e.message}", event_details: details }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      end

      private

      # Extract the earliest :project_end date and then subtract 2 years from that
      # OR return the :project_start plus one year (if no :project_end was found)
      def _find_start_date(entries:)
        start_dates = entries.map { |e| e['_source'] }.map do |dmp|
          return (Date.parse(dmp['project_end']) - 730).to_s unless dmp['project_end'].nil?

          # Or 1 year after the project start if no project end date was defined
          proj_start = (Date.parse(dmp.fetch('project_start', dmp['registered'])) + 365).to_s
        end
        start_dates.sort.last
      end

      # Search DataCite using the supplied query and then process the response
      def _query_datacite(query:, logger:)
        logger&.debug(message: "GraphQL query used", details: query)
        resp = _call_datacite(body: query, logger:)
        data = resp.is_a?(Hash) ? resp['data'] : JSON.parse(resp)
        logger&.debug(message: "Raw results from DataCite.", details: data)
        data
      end

      # Search the Pid Graph by Affiliation ROR
      def _graphql_affiliation(ror:, range:)
        {
          variables: { ror: ror },
          operationName: 'affiliationQuery',
          query: <<~TEXT
            query affiliationQuery ($ror: ID!)
            {
              organization(id: $ror) {
                id
                name
                alternateName
                works(query: "created: [#{range}]") { nodes #{_related_work_fragment } }
              }
            }
          TEXT
        }.to_json
      end

      # Search DataCite using the supplied query and then process the response
      def _fetch_and_process_works(query:, comparator:, logger:)
        logger&.debug(message: "GraphQL query used", details: query)
        resp = _call_datacite(body: query, logger:)
        data = resp.is_a?(Hash) ? resp['data'] : JSON.parse(resp)
        logger&.debug(message: "Raw results from DataCite.", details: data)
        data
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

      # Compare the related works from DataCite with the things we know about the DMP
      def _select_relevant_content(datacite_recs:, dmps:, logger:)
        return [] unless datacite_recs.is_a?(Hash) && dmps.is_a?(Array)

        works = datacite_recs.fetch('organization', {}).fetch('works', {}).fetch('nodes', [])
        comparator = Uc3DmpId::Comparator.new(dmps:, logger:)

        works.each do |work|
          comprable = _extract_comparable(hash: work)
          next unless comprable.is_a?(Hash) && !comprable['title'].nil?

          puts comprable


          #   next if work.nil?

          #   results[:"#{term}"] << work
          # end
        end

        # results
        []
      end

      # Compare the work to the DMP to see if its a possible match
      def _compare_result(comparator:, hash:)
        response = { confidence: 'None', score: 0, notes: [] }
        return response unless hash.is_a?(Hash) && !hash['title'].nil?

        # Compare the grant ids. If we have a match return the response immediately since that is
        # a very positive match!
        response = _grants_match?(array: hash['fundings'], response:)
        return response if response[:confidence] != 'None'

        response = _opportunities_match?(array: hash['fundings'], response:)
        response = _orcids_match?(array: hash['people'], response:)
        response = _last_name_and_affiliation_match?(array: hash['people'], response:)

        # Only process the following if we had some matching contributors, affiliations or opportuniy nbrs
        response = _repository_match?(array: hash['repositories'], response:) if response[:score].positive?
        response = _keyword_match?(array: hash['keywords'], response:) if response[:score].positive?
        response = _text_match?(type: 'title', text: hash['title'], response:) if response[:score].positive?
        response = _text_match?(type: 'abstract', text: hash['abstract'], response:) if response[:score].positive?
        # If the score is less than 3 then we have no confidence that it is a match
        return response if response[:score] <= 2

        # Set the confidence level based on the score
        response[:confidence] = if response[:score] > 10
                                  'High'
                                else
                                  (response[:score] > 5 ? 'Medium' : 'Low')
                                end
        response






        details_hash = _extract_comparable(hash: hash)
        return nil unless details_hash.is_a?(Hash) && !details_hash['title'].nil?

        result = comparator.compare(hash: details_hash)
        return nil if result[:score] <= 0

        src = hash.fetch('publisher', hash.fetch('member', {})&.fetch('name', nil))
        result[:source] = ['Datatcite', src].compact.join(' via ')
        result.merge(hash)
      rescue Uc3DmpId::ComparatorError => e
        logger.error(message: "Comparator error: #{e.message}", details: e.backtrace)
        nil
      end

       # Check the DataCite results to see if we should make any updates to the DMP
       def _augment_dmp(run_id:, augmenter:, dmp:, related_works:, logger:)
        aug = Uc3DmpId::Augmenter.new(run_id:, dmp:, augmenter:, logger:)
        mod_count = aug.add_modifications(works: JSON.parse(related_works.to_json))
        logger&.debug(message: "Added #{mod_count} modifications to the DMP!")
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
          name: hash['funderName'],
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

      # Search the Pid Graph by Researcher ORCID
      def _graphql_researcher(orcid:, year:)
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
          publisher {
            name
            publisherIdentifier
            publisherIdentifierScheme
          }
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
