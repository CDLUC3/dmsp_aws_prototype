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
require 'uc3-dmp-id'

module Functions
  # A service that indexes DMP-IDs into OpenSearch
  class DmpIndexer
    SOURCE = 'DMP-ID Dynamo Table Stream to OpenSearch'

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

        client = _open_search_connect(logger:) if records.any?
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
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: _dmp_to_os_doc(hash: payload, logger:),
              id: pk,
              refresh: true
            )
          else
            logger&.info(message: "Creating OpenSearch record")
            client.index(
              index: ENV['OPEN_SEARCH_INDEX'],
              body: _dmp_to_os_doc(hash: payload, logger:),
              id: pk,
              refresh: true
            )
          end

          record_count += 1
        end

        logger&.info(message: "Processed #{record_count} records.")
        "Processed #{record_count} records."
      rescue StandardError => e
        puts "ERROR: Updating OpenSearch index: #{e.message}"
        puts e.backtrace
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

      # Convert the incoming DynamoStream payload to the OpenSearch index format
      # Incoming:
      #   {
      #     "contact": {
      #       "M": {
      #         "name": { "S": "Riley, Brian" },
      #         "contact_id": {
      #           "M": {
      #             "identifier": { "S": "https://orcid.org/0000-0001-0001-0001" },
      #             "type": { "S": "orcid" }
      #           }
      #         }
      #       }
      #     },
      #     "SK": { "S": "VERSION#latest" },
      #     "description": { "S": "Update 4" },
      #     "PK": { "S": "DMP#stream_test_1" },
      #     "title": { "S": "Stream test 1" }
      #   }
      #
      # Index Doc:
      #   {
      #     "dmp_id": "stream_test_1",
      #     "title": "Stream test 1",
      #     "description": "Update 4",
      #     "contact_id": "https://orcid.org/0000-0001-0001-0001"
      #     "contact_name": "Riley"
      #   }
      def dmp_to_os_doc(hash:)
        parts = { people: [], people_ids: [], affiliations: [], affiliation_ids: [] }
        parts = parts_from_dmp(parts_hash: parts, hash:)
        parts.merge({
          dmp_id: Uc3DmpId::Helper.pk_to_dmp_id(p_key: hash.fetch('PK', {})['S'])['identifier'],
          title: hash.fetch('title', {})['S']&.downcase,
          description: hash.fetch('description', {})['S']&.downcase
        })
      end

      # Convert the contact section of the Dynamo record to an OpenSearch Document
      def parts_from_dmp(parts_hash:, hash:)
        contributors = hash.fetch('contributor', []).map { |c| c.fetch('M', {})}

        # Process the contact
        parts_hash = parts_from_person(parts_hash:, hash: hash.fetch('contact', {}).fetch('M', {}))
        # Process each contributor
        hash.fetch('contributor', []).map { |c| c.fetch('M', {})}.each do |contributor|
          parts_hash = parts_from_person(parts_hash:, hash: contributor)
        end

        # Deduplicate and remove nils and convert to lower case
        parts_hash&.each_key { |key| parts_hash[key] = parts_hash[key].compact.uniq.map(&:downcase) }
        parts_hash
      end

      # Convert the person metadata for OpenSearch
      def parts_from_person(parts_hash:, hash:)
        return parts_hash unless hash.is_a?(Hash) && hash.keys.any?

        id = hash.fetch('contact_id', hash.fetch('contributor_id', {}))['M']
        a_id = hash.fetch('dmproadmap_affiliation', {})['M']

        parts_hash[:people] << hash.fetch('name', {})['S']
        parts_hash[:people] << hash.fetch('mbox', {})['S']
        parts_hash[:affiliations] << affil.fetch('name', {})['S']

        parts_hash[:people_ids] << id.fetch('identifier', {})['S']
        parts_hash[:affiliation_ids] << a_id.fetch('affiliation_id', {}).fetch('M', {}).fetch('identifier', {})['S']
        parts_hash
      end

      # Extract all of the important information from the DMP to create our OpenSearch Doc
      def _dmp_to_os_doc(hash:, logger:)
        people = _extract_people(hash:, logger:)
        pk = Uc3DmpId::Helper.remove_pk_prefix(p_key: hash.fetch('PK', {})['S'])
        visibility = hash.fetch('dmproadmap_privacy', {})['S']&.downcase&.strip == 'public' ? 'public' : 'private'

        # Set the project start date equal to the date specified or the DMP creation date
        proj_start = hash.fetch('project', {}).fetch('L', []).first.fetch('start', {})['S']
        proj_start = hash.fetch('created', {})['S'] if proj_start.nil?

        # Set the project end date equal to the specified end OR 5 years after the start
        proj_end = hash.fetch('project', {}).fetch('L', []).first.fetch('end', {})['S']
        proj_end = Date.parse(proj_start.to_s) + 1825 if proj_end.nil?

        doc = people.merge({
          dmp_id: Uc3DmpId::Helper.format_dmp_id(value: pk, with_protocol: true),
          title: hash.fetch('title', {})['S']&.downcase,
          visibility: visibility,
          featured: hash.fetch('dmproadmap_featured', {})['S']&.downcase&.strip == '1' ? 1 : 0,
          description: hash.fetch('description', {})['S']&.downcase,
          project_start: proj_start&.to_s&.split('T')&.first,
          project_end: proj_end&.to_s&.split('T')&.first
        })
        logger.debug(message: 'New OpenSearch Document', details: { document: doc }) unless visibility == 'public'
        return doc unless visibility == 'public'

        # Attach the narrative PDF if the plan is public
        pdfs = hash.fetch('dmproadmap_related_identifiers', {}).fetch('L', []).select do |related|
          related.fetch('M', {}).fetch('descriptor', {})['S']&.downcase&.strip == 'is_metadata_for' &&
            related.fetch('M', {}).fetch('work_type', {})['S']&.downcase&.strip == 'output_management_plan'
        end
        pdf = pdfs.is_a?(Array) ? pdfs.last : pdfs

        doc[:created] = hash['created']['S']&.to_s&.split('T')&.first unless hash['created'].nil?
        doc[:modified] = hash['modified']['S']&.to_s&.split('T')&.first unless hash['modified'].nil?
        doc[:narrative_url] = pdfs.last.fetch('M', {}).fetch('identifier', {})['S'] unless pdf.nil?
        logger.debug(message: 'New OpenSearch Document', details: { document: doc })
        doc
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