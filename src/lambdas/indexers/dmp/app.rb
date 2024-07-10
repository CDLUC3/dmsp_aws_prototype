# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'opensearch-aws-sigv4'
require 'aws-sigv4'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-id'

module Functions
  # A service that indexes DMP-IDs into OpenSearch
  class DmpIndexer
    # SOURCE = 'DMP-ID Dynamo Table Stream to OpenSearch'
    SOURCE = 'DMP-ID Dynamo Table Stream to Dynamo Index'

    # Parameters
    # ----------
    # event: Hash, required
    #     DynamoDB Stream Event Input:
    #       {
    #         "eventID": "53041a9383eb551d8e1d5cc062aa7ebd",
    #         "eventName": "MODIFY",
    #         "eventVersion": "1.1",
    #         "eventSource": "aws:dynamodb",
    #         "awsRegion": "us-west-2",
    #         "dynamodb": {
    #           "ApproximateCreationDateTime": 1698878479.0,
    #           "Keys": {
    #             "SK": { "S": "VERSION#latest" },
    #             "PK": { "S": "DMP#stream_test_1" }
    #           },
    #           "NewImage": {
    #             "contact": {
    #               "M": {
    #                 "name": { "S": "Riley, Brian" },
    #                 "contact_id": {
    #                   "M": {
    #                     "identifier": { "S": "https://orcid.org/0000-0001-9870-5882" },
    #                     "type": { "S": "orcid" }
    #                   }
    #                 }
    #               }
    #             },
    #             "SK": { "S": "VERSION#latest" },
    #             "description": { "S": "Update 4" },
    #             "PK": { "S": "DMP#stream_test_1" },
    #             "title": { "S": "Stream test 1" }
    #           },
    #           "SequenceNumber": "1157980700000000064369222776",
    #           "SizeBytes": 206,
    #           "StreamViewType": "NEW_IMAGE"
    #         },
    #         "eventSourceARN": "arn:aws:dynamodb:us-west-2:MY_ACCT:table/TABLE_ID/stream/2023-11-01T20:51:23.151"
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        records = event.fetch('Records', [])

        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.is_a?(LambdaContext) ? context.aws_request_id : event['id']
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # TODO: Eventually reenable this once we have OpenSearch in a stable situation
        # client = _open_search_connect(logger:) if records.any?
        client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
        table = ENV['DYNAMO_INDEX_TABLE']
        record_count = 0

        records.each do |record|
          pk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('PK', {})['S']
          sk = record.fetch('dynamodb', {}).fetch('Keys', []).fetch('SK', {})['S']
          payload = record.fetch('dynamodb', {}).fetch('NewImage', {})
          next if pk.nil? || sk.nil? || payload.nil? || sk != Uc3DmpId::Helper::DMP_LATEST_VERSION

          logger&.debug(message: "Processing change to DynamoDB record #{pk}", details: record)

          case record['eventName']
          when 'REMOVE'
            logger&.info(message: "Removing OpenSearch record")
          when 'MODIFY'
            logger&.info(message: "Updating OpenSearch record")
            doc = _dmp_to_dynamo_index(client:, table:, hash: payload, logger:)
            # client.index(
            #   index: ENV['OPEN_SEARCH_INDEX'],
            #   body: _dmp_to_os_doc(hash: payload, logger:),
            #   id: pk,
            #   refresh: true
            # )
          else
            logger&.info(message: "Creating OpenSearch record")
            doc = _dmp_to_dynamo_index(client:, table:, hash: payload, logger:)
            # client.index(
            #   index: ENV['OPEN_SEARCH_INDEX'],
            #   body: _dmp_to_os_doc(hash: payload, logger:),
            #   id: pk,
            #   refresh: true
            # )
          end

          record_count += 1
        end

        logger&.info(message: "Processed #{record_count} records.")
        "Processed #{record_count} records."
      rescue Net::OpenTimeout => e
        puts "ERROR: Unable to establish a connection to OpenSearch! #{e.message}"
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: { message: e.message }, event:)
      rescue StandardError => e
        puts "ERROR: Updating OpenSearch index: #{e.message}"
        puts e.backtrace
        details = { message: e.message, backtrace: e.backtrace }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details:, event:)
      end

      private

      # Establish a connection to OpenSearch
      def _open_search_connect(logger:)
        # NOTE the AWS credentials are supplied to the Lambda at Runtime, NOT passed in by CloudFormation
        signer = Aws::Sigv4::Signer.new(
          service: 'es',
          region: ENV['AWS_REGION'],
          access_key_id: ENV['AWS_ACCESS_KEY_ID'],
          secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
          session_token: ENV['AWS_SESSION_TOKEN']
        )
        client = OpenSearch::Aws::Sigv4Client.new({ host: ENV['OPEN_SEARCH_DOMAIN'], log: true }, signer)
        logger&.debug(message: client&.info)

        # Create the index if it does not already exist
        index_exists = client.indices.exists(index: ENV['OPEN_SEARCH_INDEX'])
        logger&.info(message: "Creating index '#{ENV['OPEN_SEARCH_INDEX']}' because it does not exist") unless index_exists
        client.indices.create(index: ENV['OPEN_SEARCH_INDEX']) unless index_exists

        client
      rescue StandardError => e
        puts "ERROR: Establishing connection to OpenSearch: #{e.message}"
        puts e.backtrace
      end

      # Update the indices
      def _dmp_to_dynamo_index(client:, table:, hash:, logger:)
        pk = hash.fetch('PK', {})['S']
        sk = 'METADATA'

        # Fetch the existing Indexed metadata
        resp = client.get_item({
          table_name: table,
          key: { PK: pk, SK: sk },
          consistent_read: false,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        })
        original = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
        logger&.debug(message: 'Original Index for DMP metadata', details: original)

        # Generate the new Indexed metadata
        idx_rec = { PK: pk, SK: sk }.merge(_dmp_to_os_doc(hash:, logger:))

        # Update/Add the metadata for the DMP
        client.put_item(item: idx_rec, table_name: table)

        idx_payload = {
          pk:,
          modified: hash.fetch('modified', {})['S'],
          title: hash.fetch('title', {})['S'],
          abstract: hash.fetch('description', {})['S']
        }

        # Update each AFFILIATION ROR index with the DMP sort/search criteria
        new_ids = idx_rec.fetch(:affiliation_ids, []).flatten.uniq
        original_ids = original.nil? ? [] : original.fetch('affiliation_ids', []).flatten.uniq
        _sync_index(
          client:, table:, idx_pk: 'AFFILIATION_INDEX', dmp: idx_payload, original_ids:, new_ids:, logger:
        )

        # Update each PERSON_INDEX ORCID/email index with the DMP sort/search criteria
        new_ids = idx_rec.fetch(:people_ids, [])
        new_ids += idx_rec.fetch(:people, []).select { |entry| entry.include?('@') }
        new_ids = new_ids.flatten.uniq

        original_ids = original.fetch('people_ids', [])
        original_ids += original.fetch('people', []).select { |entry| entry.include?('@') }
        original_ids = original_ids.flatten.uniq
        _sync_index(
          client:, table:, idx_pk: 'PERSON_INDEX', dmp: idx_payload, original_ids:, new_ids:, logger:
        )

        # Update each FUNDER ROR index with the DMP sort/search criteria
        new_ids = idx_rec.fetch(:funder_ids, []).flatten.uniq
        original_ids = original.nil? ? [] : original.fetch('funder_ids', []).flatten.uniq
        _sync_index(
          client:, table:, idx_pk: 'FUNDER_INDEX', dmp: idx_payload, original_ids:, new_ids:, logger:
        )
      end

      def _sync_index(client:, table:, idx_pk:, dmp:, original_ids:, new_ids:, logger: nil)
        logger&.debug(message: 'Syncing indices', details: { new_ids:, original_ids:, dmp: })
        # Loop through each of the new ids we want to index
        new_ids.difference(original_ids).each do |id|
          item = _dynamo_index_get(client:, table:, key: { PK: idx_pk, SK: id }, logger:)
          logger&.debug(message: 'Adding DMP PK on index', details: item)

          # Add the DMP payload to the index (removing the old entry if it exists)
          item['dmps'] = [] if item['dmps'].nil?
          item['dmps'].delete_if { |entry| entry.is_a?(String) || entry['pk'] == dmp[:pk] }
          item['dmps'] << dmp
          _dynamo_index_put(client:, table:, item:, logger:)
        end

        # Loop through all of the original ids that no longer appear in the new ids
        original_ids.difference(new_ids).each do |id|
          item = _dynamo_index_get(client:, table:, key: { PK: idx_pk, SK: id }, logger:)
          next if item.fetch('dmps', []).empty?

          # Remove the DMP Payload from that index
          logger&.debug(message: 'Removing DMP PK from index', details: item)
          item['dmps'] = item['dmps'].reject { |og| og['pk'] == dmp[:pk] }
          _dynamo_index_put(client:, table:, item:, logger:)
        end
      end

      # Fetch the index record from the DB
      def _dynamo_index_get(client:, table:, key:, logger: nil)
        resp = client.get_item({
          table_name: table,
          key:,
          consistent_read: false,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        })

        logger.debug(message: "#{SOURCE} fetched INDEX ID: #{key}") if logger.respond_to?(:debug)
        item = resp[:item].is_a?(Array) ? resp[:item].first : resp[:item]
        item.nil? ? JSON.parse(key.to_json) : item
      end

      # Add/update an index record
      def _dynamo_index_put(client:, table:, item:, logger: nil)
        resp = client.put_item({
          table_name: table,
          item:,
          return_consumed_capacity: logger&.level == 'debug' ? 'TOTAL' : 'NONE'
        })
        resp
      end

      # Extract all of the important information from the DMP to create our OpenSearch Doc
      def _dmp_to_os_doc(hash:, logger:)
        people = _extract_people(hash:, logger:)
        pk = Uc3DmpId::Helper.remove_pk_prefix(p_key: hash.fetch('PK', {})['S'])
        visibility = hash.fetch('dmproadmap_privacy', {})['S']&.downcase&.strip == 'public' ? 'public' : 'private'

        project = hash.fetch('project', {}).fetch('L', [{}]).first['M']
        project = {} if project.nil?
        # Set the project start date equal to the date specified or the DMP creation date
        proj_start = project.fetch('start', hash.fetch('created', {}))['S']
        # Set the project end date equal to the specified end OR 5 years after the start
        proj_end = project.fetch('end', {})['S']
        proj_end = (Date.parse(proj_start.to_s) + 1825).to_s if proj_end.nil? && !proj_start.nil?

        funding = project.fetch('funding', {}).fetch('L', [{}]).first.fetch('M', {})
        doc = people.merge(_extract_funding(hash: funding, logger:))
        doc = doc.merge(_repos_to_os_doc_parts(datasets: hash.fetch('dataset', {}).fetch('L', [])))
        doc = doc.merge({
          dmp_id: Uc3DmpId::Helper.remove_pk_prefix(p_key: pk),
          title: hash.fetch('title', {})['S']&.downcase,
          visibility: visibility,
          featured: hash.fetch('dmproadmap_featured', {})['S']&.downcase&.strip == '1' ? 1 : 0,
          description: hash.fetch('description', {})['S']&.downcase,
          project_start: proj_start&.to_s&.split('T')&.first,
          project_end: proj_end&.to_s&.split('T')&.first,
          created: hash.fetch('created', {})['S']&.to_s&.split('T')&.first,
          modified: hash.fetch('modified', {})['S']&.to_s&.split('T')&.first,
          registered: hash.fetch('registered', {})['S']&.to_s&.split('T')&.first
        })
        logger.debug(message: 'New OpenSearch Document', details: { document: doc }) unless visibility == 'public'
        return doc unless visibility == 'public'

        # Attach the narrative PDF if the plan is public
        works = hash.fetch('dmproadmap_related_identifiers', hash.fetch('dmproadmap_related_identifier', {})).fetch('L', [])
        doc[:narrative_url] = _extract_narrative(works:, logger:)
        logger.debug(message: 'New OpenSearch Document', details: { document: doc })
        doc
      end

      # Extract the important funding info
      def _extract_funding(hash:, logger:)
        return {} unless hash.is_a?(Hash)

        id = hash.fetch('funder_id', {}).fetch('M', {}).fetch('identifier', {})['S']
        {
          funder_ids: [id].compact.uniq,
          funders: [hash.fetch('name', {})['S']&.downcase&.strip].compact.uniq,
          funder_opportunity_ids: [
            hash.fetch('dmproadmap_funding_opportunity_id', {})['S']&.downcase&.strip,
            hash.fetch('dmproadmap_project_number', {})['S']&.downcase&.strip
          ].compact.uniq,
          grant_ids: [hash.fetch('grant_id', {}).fetch('M', {}).fetch('identifier', {})['S']].compact.uniq,
          funding_status: hash.fetch('funding_status', {}).fetch('S', 'planned')
        }
      end

      # Extarct the latest link to the narrative PDF
      def _extract_narrative(works:, logger:)
        pdfs = works.map { |entry| entry.fetch('M', {}) }.select do |work|
          work.fetch('descriptor', {})['S'] == 'is_metadata_for' &&
            work.fetch('work_type', {})['S'] == 'output_management_plan'
        end
        return nil if pdfs.empty? || pdfs.first.nil?

        pdfs.last.fetch('identifier', {})['S']
      end

      # Extract the important information from each contact and contributor
      def _extract_people(hash:, logger:)
        return {} unless hash.is_a?(Hash)

        # Fetch the important parts from each person
        people = hash.fetch('contributor', {})['L']&.map { |contrib| _process_person(hash: contrib) }
        people = [] if people.nil?
        people << _process_person(hash: hash['contact'])
        logger.debug(message: "Extracted the people from the DMP", details: { people: people })

        # Distill the individual people
        parts = _people_to_os_doc_parts(people:)
        # Dedeplicate and remove any nils
        parts = parts.each_key { |key| parts[key] = parts[key]&.compact&.uniq }
        parts
      end

      # Combine all of the people metadata into arrays for our OpenSearch Doc
      def _people_to_os_doc_parts(people:)
        parts = { people: [], people_ids: [], affiliations: [], affiliation_ids: [] }

        # Add each person's info to the appropriate part or the OpenSearch doc
        people.each do |person|
          parts[:people] << person[:name] unless person[:name].nil?
          parts[:people] << person[:email] unless person[:email].nil?
          parts[:people_ids] << person[:id] unless person[:id].nil?
          parts[:affiliations] << person[:affiliation] unless person[:affiliation].nil?
          parts[:affiliation_ids] << person[:affiliation_id] unless person[:affiliation_id].nil?
        end
        parts
      end

      # Retreive all of the repositories defined for the research outputs
      def _repos_to_os_doc_parts(datasets:)
        parts = { repos: [], repo_ids: [] }
        return parts unless datasets.is_a?(Array) && datasets.any?

        outputs = datasets.map { |dataset| dataset.fetch('M', {}) }

        outputs.each do |output|
          hosts = output.fetch('distribution', {}).fetch('L', []).map { |d| d.fetch('M', {}).fetch('host', {})['M'] }
          next unless hosts.is_a?(Array) && hosts.any?

          hosts.each do |host|
            next if host.nil?

            parts[:repos] << host.fetch('title', {})['S']
            parts[:repo_ids] << host.fetch('url', {})['S']
            parts[:repo_ids] << host.fetch('dmproadmap_host_id', {}).fetch('M', {}).fetch('identifier', {})['S']
          end
        end
        parts[:repo_ids] = parts[:repo_ids].compact.uniq
        parts[:repos] = parts[:repos].compact.uniq
        parts
      end

      # Extract the important patrts of the contact/contributor from the DynamoStream image
      #   "M": {
      #     "name": { "S": "DMPTool Researcher" },
      #     "dmproadmap_affiliation": {
      #       "M": {
      #         "name": { "S": "University of California, Office of the President (UCOP)" },
      #         "affiliation_id": {
      #           "M": {
      #             "identifier": { "S": "https://ror.org/00pjdza24" },
      #             "type": { "S": "ror" }
      #           }
      #         }
      #       }
      #     },
      #     "contact_id|contributor_id": {
      #       "M": {
      #         "identifier": { "S": "https://orcid.org/0000-0002-5491-6036" },
      #         "type": { "S": "orcid" }
      #       }
      #     },
      #     "mbox": { "S": "dmptool.researcher@gmail.com" }
      #     "role": {
      #       "L": [{ "S": "http://credit.niso.org/contributor-roles/investigation" }]
      #     }
      #   }
      def _process_person(hash:)
        return {} unless hash.is_a?(Hash) && !hash['M'].nil?

        id_type = hash['M']['contact_id'].nil? ? 'contributor_id' : 'contact_id'
        affiliation = _process_affiliation(hash: hash['M'].fetch('dmproadmap_affiliation', {}))

        {
          name: hash['M'].fetch('name', {})['S']&.downcase,
          email: hash['M'].fetch('mbox', {})['S']&.downcase,
          id: _process_id(hash: hash['M'].fetch(id_type, {})),
          affiliation: affiliation[:name],
          affiliation_id: affiliation[:id]
        }
      end

      # Extract the important patrts of the affiliation from the DynamoStream image
      #
      #  "M": {
      #    "name": { "S": "University of California, Office of the President (UCOP)" },
      #    "affiliation_id": {
      #      "M": {
      #        "identifier": { "S": "https://ror.org/00pjdza24" },
      #        "type": { "S": "ror" }
      #      }
      #    }
      #  }
      def _process_affiliation(hash:)
        return {} unless hash.is_a?(Hash) && !hash['M'].nil?

        {
          name: hash['M'].fetch('name', {})['S']&.downcase,
          id: _process_id(hash: hash['M'].fetch('affiliation_id', {}))
        }
      end

      # Extract the important patrts of the identifier from the DynamoStream image
      #
      #    "M": {
      #      "identifier": { "S": "https://ror.org/00987cb86" },
      #      "type": { "S": "ror" }
      #    }
      def _process_id(hash:)
        hash.is_a?(Hash) ? hash.fetch('M', {}).fetch('identifier', {})['S']&.downcase : nil
      end
    end
  end
end