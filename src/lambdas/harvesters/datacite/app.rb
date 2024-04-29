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
require 'uc3-dmp-id'

module Functions
  # A service that queries DataCite GraphQL API
  class DataCiteHarvester
    SOURCE = 'DataCite Harvester'

    DMP_HARVESTER_MODS_SK = 'HARVESTER_MODS'

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

        # Query DataCite to determine the size of the potential output
        query = _graphql_page_info_query(ror:, range:)
        logger&.debug(message: 'Querying DataCite:', details: query)
        datacite_recs = _query_datacite(query:, logger:)
        return true unless datacite_recs.is_a?(Hash)

        # Fetch the start cursor and the total work count from the response
        # Unfortunately DataCite throws an error if we try to fetch the current cursor from `edges { cursor }`
        # so we will instead pass the startCursor to the real query and either the full item count of 1000
        meta = datacite_recs.fetch('organization', {}).fetch('works', {})
        start_cursor = meta.fetch('pageInfo', {})['startCursor']
        work_count = meta.fetch('totalCount', '0').to_i
        work_count = 1000 if workCount > 1000

        # Query DataCite for the list of works
        query = _graphql_affiliation(ror:, range:, start_cursor:, work_count:)
        logger&.debug(message: 'Querying DataCite:', details: query)
        datacite_recs = _query_datacite(query:, logger:)

        # See if the returned DataCite info has any matches to our DMSPs
        matches = _select_relevant_content(datacite_recs:, dmps: details['dmps'], logger:)
        return true unless matches.is_a?(Array) && matches.any?

        # Update the relevant DMSPs
        _process_matches(dynamo_client:, table:, matches:, logger:)

        # Send log to admins
        deets = { message: "Scanned DataCite for Org #{ror}. Found #{matches.count} possible matches!", matches: }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)

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
        return [] if resp.nil?

        data = resp.is_a?(Hash) ? resp['data'] : JSON.parse(resp)
        logger&.debug(message: "Raw results from DataCite.", details: data)
        data
      end

      # First hot Datacite to determine the starting cursor and the total number of records.
      # Unfortunately DataCite throws an error if we try to fetch the current cursor from `edges { cursor }`
      # so we will instead pass the startCursor to the real query and either the full item count of 1000
      def _graphql_page_info_query(ror:, range:)
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
                works(query: "created: [#{range}]") {
                  totalCount
                  pageInfo {
                    startCursor
                    endCursor
                    hasNextPage
                  }
                }
              }
            }
          TEXT
        }.to_json
      end

      # Search the Pid Graph by Affiliation ROR
      def _graphql_affiliation(ror:, range:, start_cursor:, work_count:)
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
                works(query: "created: [#{range}]", first: #{work_count}, after: "#{start_cursor}") {
                  nodes #{_related_work_fragment }
                }
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
            resp = Uc3DmpExternalApi::Client.call(url: GRAPHQL_ENDPOINT, method: :post, body: body, timeout: 120, logger:)

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
        relevant = []
        return relevant unless datacite_recs.is_a?(Hash) && dmps.is_a?(Array)

        works = datacite_recs.fetch('organization', {}).fetch('works', {}).fetch('nodes', [])
        comparator = Uc3DmpId::Comparator.new(dmps:, logger:)

        works.each do |work|
          comprable = _extract_comparable(hash: work)
          next unless comprable.is_a?(Hash) && !comprable['title'].nil?

          logger&.debug(message: 'DataCite record reduced to it\'s comprable parts:', details: comprable)
          result = comparator.compare(hash: comprable)
          next unless result.is_a?(Hash) && result[:score] >= 3

          src = work.fetch('publisher', work.fetch('member', {}))&.fetch('name', nil)
          result[:source] = ['Datacite', src].compact.join(' via ')
          result = result.merge({ work: })
          logger&.info(message: 'Uc3DmpId::Comparator potential match:', details: result)
          relevant << result
        end
        relevant
      end

      # Add the relevant matches from DataCite to the DMP-IDs HARVESTER_MODS doc
      def _process_matches(dynamo_client:, table:, matches:, logger:)
        matches.each do |match|
          next unless match[:work].is_a?(Hash) && match[:work]['id']

          work_id = match[:work]['id']
          # Fetch existing HARVESTER_MODS record (or initialize it)
          mods_rec = _get_mods_record(client: dynamo_client, table:, dmp_id: match[:dmp_id], logger:)
          mods_rec = JSON.parse({ PK: match[:dmp_id], SK: 'HARVESTER_MODS', tstamp: Time.now.utc.iso8601 }.to_json)
          # Fetch the full DMP record
          dmp = _get_dmp(client: dynamo_client, table:, dmp_id: match[:dmp_id], logger:)
          # Skip if it already has the DOI OR the DMP already knows about it
          next unless mods_rec.fetch('related_works', {})[:"#{work_id}"].nil? &&
                      dmp.fetch('dmproadmap_related_identifiers', []).select { |ri| ri['identifier'] == work_id }.empty?
          # Skip if the entry is for the current DMP!
          next if work_id.gsub('DMP#', '').gsub('https://', '').downcase == match[:dmp_id].gsub('DMP#', '').gsub('https://', '').downcase

          tstamp = mods_rec['tstamp']
          # Prepare the related works (skip if they are already on the full DMP record)
          related_work_mod = _prepare_related_work_mod(match:, logger:)
          logger&.debug(message: 'Related work mod found:', details: related_work_mod)

          # Refetch the DMP mods record to check the :tstamp and use the new one if applicable
          mods_rec_check = _get_mods_record(client: dynamo_client, table:, dmp_id: match[:dmp_id], logger:)
          mods_rec = mods_rec_check if mods_rec_check.is_a?(Hash) && tstamp != mods_rec_check['tstamp']

          mods_rec['related_works'] = {} if mods_rec['related_works'].nil?
          mods_rec['related_works'][:"#{work_id}"] = related_work_mod

          puts related_work_mod
          puts mods_rec

          # Update the DMP mods record
          dynamo_client.put_item(item: mods_rec, table_name: table)
        end
      end

      # Convert CamelCase `IsCitedBy` to underscores `is_cited_by`
      def _descriptor_to_underscore(str:)
        str.tap do |s|
          s.gsub!(/(.)([A-Z])/,'\1_\2')
          s.downcase!
        end
        str
      end

      def _prepare_related_work_mod(match:, logger:)
        work = match[:work]
        typ = work.fetch('type', 'dataset')&.downcase&.strip
        citation = Uc3DmpCitation::Citer.bibtex_to_citation(uri: work['id'], bibtex_as_string: work['bibtex'])
        secondary_works = []
        work.fetch('relatedIdentifiers', []).each do |related|
          next if related['relatedIdentifier'].nil? || related['relationType'] == 'IsCitedBy'

          secondary_works << {
            type: related.fetch('relatedIdentifierType', 'url'),
            identifier: related['relatedIdentifier'],
            descriptor: _descriptor_to_underscore(str: related.fetch('relationType', 'references'))
          }
        end

        {
          provenance: match[:source],
          score: match[:score],
          confidence: match[:confidence],
          logic: match[:notes],
          discovered_at: Time.now.utc.iso8601,
          status: 'pending',
          type: 'doi',
          identifier: work['id'],
          descriptor: 'references',
          work_type: typ == 'journalarticle' ? 'article' : typ,
          citation:,

          secondary_works: secondary_works&.flatten&.compact&.uniq
        }
      end

      # Fetch the latest Harvester mods for the DMP
      def _get_mods_record(client:, table:, dmp_id:, logger:)
        resp = client.get_item(key: { PK: dmp_id, SK: DMP_HARVESTER_MODS_SK }, table_name: table)
        resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
      rescue Aws::Errors::ServiceError => e
        logger&.error(message: "Unable to fetch the Harvester mods record #{dmp_id} - #{e.message}", details: e.backtrace)
      end

      # Fetch the latest version of the DMP
      def _get_dmp(client:, table:, dmp_id:, logger:)
        resp = client.get_item(key: { PK: dmp_id, SK: Uc3DmpId::Helper::DMP_LATEST_VERSION }, table_name: table)
        resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
      rescue Aws::Errors::ServiceError => e
        logger&.error(message: "Unable to fetch DMP ID record #{dmp_id} - #{e.message}", details: e.backtrace)
      end

      # Convert the DataCite :work into a hash for the Uc3DmpId::Comparator.
      # It is expecting the same format as an OpenSearch document:
      # {
      #   "people": ["john doe", "jdoe@example.com"],
      #   "people_ids": ["https://orcid.org/0000-0000-0000-ZZZZ"],
      #   "affiliations": ["example college"],
      #   "affiliation_ids": ["https://ror.org/00000zzzz"],
      #   "funder_ids": ["https://doi.org/10.13039/00000000000"],
      #   "funders": ["example funder (example.gov)"],
      #   "funder_opportunity_ids": ["485yt8325ty"],
      #   "grant_ids": [],
      #   "title": "example data management plan",
      #   "description": "the example project abstract"
      # }
      def _extract_comparable(hash:)
        return nil unless hash.is_a?(Hash)

        people = hash.fetch('creators', []).map { |entry| _extract_person(hash: entry) }
        people << hash.fetch('contributors', []).map { |entry| _extract_person(hash: entry) }
        people = people&.flatten&.compact&.uniq

        people_parts = { people: [], people_ids: [], affiliations: [], affiliation_ids: [] }
        people.each do |person|
          people_parts[:people] << person[:name] unless person[:name].nil?
          people_parts[:people_ids] << person[:id] unless person[:id].nil?
          people_parts[:affiliations] << person[:affiliations] unless person[:affiliations].nil?
          people_parts[:affiliation_ids] << person[:affiliation_ids] unless person[:affiliation_ids].nil?
        end

        fundings = hash.fetch('fundingReferences', []).map { |entry| _extract_funding(hash: entry) }
        funder_parts = { funders: [], funder_ids: [], grant_ids: [] }
        fundings.each do |funding|
          funder_parts[:funders] << funding[:name] unless funding[:name].nil?
          funder_parts[:funder_ids] << funding[:id] unless funding[:id].nil?
          funder_parts[:grant_ids] << funding[:grant] unless funding[:grant].nil?
        end

        repo = hash['repository'].nil? ? {} : hash['repository']

        JSON.parse({
          title: hash.fetch('titles', []).map { |entry| entry['title'] }.join(' '),
          abstract: hash.fetch('descriptions', []).map { |entry| entry['description'] }.join(' '),
          people: people_parts[:people].compact.uniq,
          people_ids: people_parts[:people_ids].compact.uniq,
          affiliations: people_parts[:affiliations].flatten.compact.uniq,
          affiliation_ids: people_parts[:affiliation_ids].flatten.compact.uniq,
          funders: funder_parts[:funders].compact.uniq,
          funder_ids: funder_parts[:funder_ids].compact.uniq,
          grant_ids: funder_parts[:grant_ids].flatten.compact.uniq,
          repos: [repo['name']&.downcase&.strip].compact,
          repo_ids: [repo['url'], repo['re3dataUrl']].compact.uniq
        }.to_json)
      end

      # Convert the incoming DataCite entry for the person into the hash for the Uc3DmpId::Comparator
      def _extract_person(hash:)
        # Names come through as `last, first` so reverse that so it's `first last`
        name = hash['name']&.downcase&.strip&.split(', ')&.reverse&.join(' ')
        name = [hash['givenName'], hash['familyName']].compact.map { |i| i.downcase.strip }.join(' ') if name.nil?
        affil = hash.fetch('affiliation', {})
        {
          id: hash['id'],
          name: name,
          affiliations: affil.map { |entry| entry['name']&.downcase&.strip },
          affiliation_ids: affil.map { |entry| entry['id']&.downcase&.strip }
        }
      end

       # Convert the incoming DataCite entry for the person into the hash for the Uc3DmpId::Comparator
       def _extract_funding(hash:)
        grants = [hash['awardUri']&.downcase&.strip, hash['awardNumber']&.downcase&.strip]
        {
          id: hash['funderIdentifier'],
          name: hash['funderName']&.downcase&.strip,
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
