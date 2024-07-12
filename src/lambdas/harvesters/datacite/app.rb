# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'date'
require 'httparty'
require 'json'
require 'text'
require 'uri'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-external-api'
require 'uc3-dmp-id'

module Functions
  # A service that queries DataCite REST API
  class DataCiteHarvester
    SOURCE = 'DataCite Harvester'

    DMP_HARVESTER_MODS_SK = 'HARVESTER_MODS'

    REST_ENDPOINT = 'https://api.datacite.org/dois?affiliation=true&publisher=true&query='
    REST_TIMEOUT_SECONDS = 120

    MSG_REST_FAILURE = 'Unable to query the DataCite REST API at this time.'
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
        index_table = ENV['DYNAMO_INDEX_TABLE']
        logger.debug(message: 'Incoming details from event', details: details) if logger.respond_to?(:debug)

        ror = details['ror']

        # Fetch all of the individual DMP's metadata
        dmps = _fetch_dmp_metadata(client: dynamo_client, table: index_table, dmps:  details['dmps'],
                                  logger:)
        logger&.debug(message: 'Full DMP metadata', details: dmps)
        # Find the start and end years for our DataCite search
        range = _find_date_range(entries: dmps)
        return true if dmps.empty? || range.empty?

        # Query DataCite for the list of works for each unique person
        people = dmps.map { |dmp| dmp['people'] }.flatten.reject { |p| p.nil? || p.include?('@') }
        people = people.compact.uniq
        years = "(#{range.join('+OR+')})"
        datacite_recs = []
        logger&.debug(message: 'Query criteria:', details: { people:, years: })
        people.each do |person|
          query = "creators.name:#{person.gsub(/\s/, '+')}+AND+publicationYear:#{years}"
          logger&.debug(message: 'Querying DataCite:', details: query)
          datacite_recs << _query_datacite(query:, logger:)
        end
        return true if datacite_recs.nil? || datacite_recs.empty?

        # See if the returned DataCite info has any matches to our DMSPs
        datacite_recs = datacite_recs.flatten.uniq.compact.map { |hash| hash['attributes'] }
        matches = _select_relevant_content(datacite_recs:, dmps:, logger:)
        return true unless matches.is_a?(Array) && matches.any?

        # Update the relevant DMSPs
        logger&.debug(message: 'Relevant content found:', details: matches)
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
      def _find_date_range(entries:)
        years = []
        entries.each do |dmp|
          if dmp['project_end'].nil? && (!dmp['project_start'].nil? || !dmp['registered'].nil?)
            # No specified project end date, so set the range to 1 to 10 years after the start
            date = Date.parse(dmp.fetch('project_start', dmp['registered']))
            years << (date + 365).year
            years << (date + 1826).year
          else
            # Otherwise use 2 years before and after the specified project end date
            years << (Date.parse(dmp['project_end']) - 730).year
            years << (Date.parse(dmp['project_end']) + 730).year
          end
        end
        current_year = Date.today.year
        # Create a range of years for our DataCite query. Cut it off at the current year
        years = years.uniq.sort.reject { |year| year > current_year }
        # If there is only one year return it
        return years if years.length <= 1

        # Determine all of the years between the start and end and return them and sort
        start_year = years.first
        gap = years.last - years.first
        years = [years.first]
        gap.times { |i| years << start_year + (i + 1) }
        years
      end

      # Search DataCite using the supplied query and then process the response
      def _query_datacite(query:, logger:)
        logger&.debug(message: "REST query used", details: query)
        resp = _call_datacite(query:, logger:)
        return [] if resp.nil?

        data = resp.is_a?(Hash) ? resp['data'] : JSON.parse(resp)
        logger&.debug(message: "Raw results from DataCite.", details: data)
        data
      end

      # Call DataCite
      def _call_datacite(query:, logger:)
        cntr = 0
        while cntr <= 2
          begin
            url = "#{REST_ENDPOINT}#{query}"
            resp = Uc3DmpExternalApi::Client.call(url:, method: :get, timeout: 300, logger:)

            logger&.info(message: MSG_EMPTY_RESPONSE, details: resp) if resp.nil? || resp.to_s.strip.empty?
            payload = resp unless resp.nil? || resp.to_s.strip.empty?
            cntr = 3 unless payload.nil?
          rescue Net::ReadTimeout
            logger&.info(message: 'Httparty timeout', details: query)
            sleep(3)
          rescue StandardError => e
            logger&.error(message: "Failure calling DataCite #{e.message}")
            cntr = 3
          end

          cntr += 1
        end
        payload
      end

      # Compare the related works from DataCite with the things we know about the DMP
      def _select_relevant_content(datacite_recs:, dmps:, logger:)
        relevant = []
        return relevant unless datacite_recs.is_a?(Array) && dmps.is_a?(Array)

        comparator = Uc3DmpId::Comparator.new(dmps:, logger:)
        datacite_recs.each do |work|
          logger&.debug(message: 'DataCite work:', details: work)
          # Skip DMPs
          next if work.fetch('types', {})['resourceType'] == 'OutputManagementPlan'

          comprable = _extract_comparable(hash: work)
          next unless comprable.is_a?(Hash) && !comprable['title'].nil?

          result = comparator.compare(hash: comprable)
          logger&.debug(message: 'Comparison result:', details: result)
          next unless result.is_a?(Hash) && result[:score] >= 2

          src = work.fetch('publisher', {}).fetch('name', nil)
          result[:source] = ['Datacite', src].compact.join(' via ')
          result = result.merge({ work: })
          logger&.info(message: 'Uc3DmpId::Comparator potential match:', details: result)
          relevant << result
        end
        relevant
      end

      # Fetch the Metadata entry for each of the DMP PKs
      def _fetch_dmp_metadata(client:, table:, dmps:, logger: nil)
        dmps.map do |hash|
          resp = client.get_item({
            table_name: table,
            key: { PK: hash['PK'], SK: 'METADATA' },
            consistent_read: false,
            return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
          })

          resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
        end
      end

      # Add the relevant matches from DataCite to the DMP-IDs HARVESTER_MODS doc
      def _process_matches(dynamo_client:, table:, matches:, logger:)
        matches.each do |match|
          next unless match[:work].is_a?(Hash) && match[:work]['doi']

          work_id = match[:work]['doi']
          work_id = "https://doi.org/#{work_id}" unless work_id.start_with?('http')
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
          related_work_mod = _prepare_related_work_mod(work_id:, match:, logger:)
          logger&.debug(message: 'Related work mod found:', details: related_work_mod)

          # Refetch the DMP mods record to check the :tstamp and use the new one if applicable
          mods_rec_check = _get_mods_record(client: dynamo_client, table:, dmp_id: match[:dmp_id], logger:)
          mods_rec = mods_rec_check if mods_rec_check.is_a?(Hash) && tstamp != mods_rec_check['tstamp']

          mods_rec['related_works'] = {} if mods_rec['related_works'].nil?
          mods_rec['related_works'][:"#{work_id}"] = related_work_mod

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

      def _prepare_related_work_mod(work_id:, match:, logger:)
        work = match[:work]
        typs = work.fetch('types', {})
        typ = typs['resourceTypeGeneral'].nil? ? typs.fetch('resourceType', 'dataset') : typs['resourceTypeGeneral']
        typ = typ&.downcase&.strip
        # citation = Uc3DmpCitation::Citer.bibtex_to_citation(uri:, bibtex_as_string: work['bibtex'])
        begin
          citation = Uc3DmpCitation::Citer.fetch_citation(doi: work['doi'], work_type: typ, logger:)
        rescue StandardError => e
          logger&.error(message: "Failed to fetch citation for #{work['doi']} - #{e.message}", details: e.backtrace)
        end
        secondary_works = []
        work.fetch('relatedIdentifiers', []).each do |related|
          next if related['relatedIdentifier'].nil? || related['relationType'] == 'IsCitedBy'

          secondary_works << {
            type: related.fetch('relatedIdentifierType', 'url'),
            identifier: related['relatedIdentifier'],
            descriptor: _descriptor_to_underscore(str: related.fetch('relationType', 'references'))
          }
        end

        begin
          uri = URI(work_id)
        rescue StandardError => e
          logger&.error(message: "#{work_id} is not a valid URI!")
        end

        {
          provenance: match[:source],
          score: match[:score],
          confidence: match[:confidence],
          logic: match[:notes],
          discovered_at: Time.now.utc.iso8601,
          status: 'pending',
          type: 'doi',
          domain: "#{uri.scheme}://#{uri.host}/",
          identifier: work['doi'],
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
          people_parts[:people] << person[:name].flatten.compact.uniq if person[:name].is_a?(Array)
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
          people: people_parts[:people].flatten.compact.uniq,
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
        affil = hash.fetch('affiliation', [])
        {
          id: hash['id'],
          name: [hash['name']&.downcase&.strip, name],
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
    end
  end
end
