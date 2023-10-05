# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-external-api'
require 'uc3-dmp-id'

module Functions
  # Lambda function that is invoked by SNS and communicates with EZID to register/update DMP IDs
  # rubocop:disable Metrics/ClassLength
  class EzidPublisher
    SOURCE = 'EzidPublisher'

    APPLICATION_NAME = 'DMPTool'
    DEFAULT_CONTRIBUTOR_ROLE = 'ProjectLeader'
    DEFAULT_LANGUAGE = 'en'
    DEFAULT_RESOURCE_TYPE = 'Data Management Plan'
    DOI_URL = 'http://doi.org'

    MSG_EZID_FAILURE = 'Communication issue with the EZID API.'

    # TODO: get the correct Fundref scheme from DataCite
    SCHEMES = {
      fundref: 'http://dx.doi.org/',
      grid: 'https://www.grid.ac/',
      isni: 'http://www.isni.org/',
      orcid: 'https://orcid.org/',
      ror: 'https://ror.org/'
    }.freeze

    TAB = '  '
    BREAK = '\n'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input:
    #       {
    #         "version": "0",
    #         "id": "5c9a3747-293c-59d7-dcee-a2210ac034fc",
    #         "detail-type": "EZID update",
    #         "source": "dmphub.uc3dev.cdlib.net:lambda:event_publisher",
    #         "account": "1234567890",
    #         "time": "2023-02-14T16:42:06Z",
    #         "region": "us-west-2",
    #         "resources": [],
    #         "detail": {
    #           "PK": "DMP#doi.org/10.12345/ABC123",
    #           "SK": "VERSION#latest",
    #           "dmphub_provenance_id": "PROVENANCE#example",
    #           "dmproadmap_links": {
    #             "download": "https://example.com/api/dmps/12345.pdf",
    #           }
    #         }
    #       }
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

    # Returns
    # ------
    # statusCode: Integer, required
    # body: String, required (JSON parseable)
    #     API Gateway Lambda Proxy Output Format: dict
    #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
    #
    #     { "statusCode": 200, "body": "{\"message\":\"Success\""}" }
    #
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
        provenance_pk = json['dmphub_provenance_id']
        dmp_pk = json['PK']
        if provenance_pk.nil? || dmp_pk.nil?
          _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS],
                   event:)
        end

        # Check the SSM Variable that will disable interaction with EZID (specifically used for
        # tests in production to verify that we are sending a valid payload to EZID)
        skip_ezid = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_debug_mode,
                                                           logger:)&.to_s&.downcase == 'true'
        # Check the SSM Variable that will pause interaction with EZID (specifically used for
        # periods when EZID will be down for an extended period)
        paused = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_paused, logger:)&.to_s&.downcase == 'true'

        # If submissions are paused, toss the event into the EventBridge archive where it can be
        # replayed at a later time
        if paused
          logger.info(message: 'EZID submissions paused: You can replay events from the archive when ready.',
                      details: json)
          deets = { message: 'EZID Paused', event_details: json }
          Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
        else
          # Load the DMP metadata
          dmp = Uc3DmpId::Finder.by_pk(p_key: dmp_pk, logger:)
          # _respond(status: 404, errors: [Uc3DmpId::MSG_DMP_NOT_FOUND], event: event) if dmp.nil?

          dmp_id = dmp.fetch('dmp', {}).fetch('dmp_id', {})['identifier'].gsub(%r{https?://}, '').gsub(
            ENV.fetch('DMP_ID_BASE_URL', nil), ''
          )
          dmp_id = dmp_id[1..dmp_id.length] if dmp_id.start_with?('/')
          ezid_url = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_api_url, logger:)
          ezid_url = "#{ezid_url}/" unless ezid_url.end_with?('/')
          base_url = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :base_url, logger:)

          url = "#{ezid_url}id/doi:#{dmp_id}?update_if_exists=yes"
          landing_page_url = "#{base_url}/dmps/#{dmp_id}"
          datacite_xml = dmp_to_datacite_xml(dmp_id:, dmp: dmp['dmp'])&.gsub(/[\r\n]/, ' ')
          logger.error(message: "Failed to build DatCite XML for #{dmp_id}", details: dmp) if datacite_xml.nil?

          payload = <<~TEXT
            _target: #{landing_page_url}
            datacite: #{datacite_xml}
          TEXT
          logger.debug(message: 'Prepared DMP ID metadata for EZID.', details: payload)

          if skip_ezid
            logger.info(message: 'EZID is currently in Debug mode. Skipping EZID submission', details: payload)
          else
            headers = {
              'Content-Type': 'text/plain',
              Accept: 'text/plain'
            }
            auth = {
              username: Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_client_id, logger:),
              password: Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_client_secret, logger:)
            }
            logger.info(message: "Sending updated DMP ID metadata to EZID for #{dmp_id}")
            logger.debug(message: "Sending DMP ID metadata to EZID for #{dmp_id}",
                         details: { url:, headers:, payload: payload.to_s })
            Uc3DmpExternalApi::Client.call(url:, method: :put, body: payload.to_s, basic_auth: auth,
                                           additional_headers: headers, logger:)
          end
        end
      rescue Uc3DmpId::FinderError => e
        logger.error(message: e.message, details: e.backtrace)
      rescue Uc3DmpExternalApi::ExternalApiError => e
        # EZID returned an error, so notify the admin. They can replay once the issue is resolved
        logger.error(message: e.message, details: json)
        deets = { message: "EZID returned an error #{e.message}", event_details: json }
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
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

      # Convert the DMP JSON into Datacite XML
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def dmp_to_datacite_xml(dmp_id:, dmp:)
        return nil if dmp_id.nil? || dmp.nil? ||
                      dmp.fetch('contact', {}).fetch('contact_id', {})['identifier'].nil?

        contributors = [
          { json: dmp['contact']['dmproadmap_affiliation'], type: 'Producer' }
        ]
        contributors << dmp.fetch('contributor', []).map do |contributor|
          roles = contributor.fetch('role', [])
          roles.map { |_role| { json: contributor, type: contributor_role(value: contributor['role']) } }
        end
        contributors << dmp.fetch('dmproadmap_sponsors', []).map do |facility|
          { json: facility, type: 'Sponsor' }
        end
        contributors = contributors.flatten.compact.uniq

        fundings = dmp.fetch('project', []).first&.fetch('funding', [])
        fundings = fundings.map do |fund|
          id = fund.fetch('funder_id', {})
          {
            name: fund['name'],
            type: id['type'],
            identifier: %w[fundref ror].include?(id['type']&.downcase) ? id['identifier'] : nil,
            grant: id['grant_id'],
            title: dmp['title']
          }
        end

        # The EZID ANVL parser is really whiny about the alignment/layout and the whitespace
        # in general of the Datacite XML bit. Be extremely careful when editing the file
        #
        # DataCite is expecting (see: https://ezid.cdlib.org/doc/apidoc.html#profile-datacite):
        #
        #  <?xml version="1.0"?>
        #  <resource xmlns="http://datacite.org/schema/kernel-4"
        #            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
        #            xsi:schemaLocation="...">
        #    <identifier identifierType="DOI">(:tba)</identifier>
        #    ...
        #  </resource>
        #
        xml = <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          #{TAB}<resource xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          #{TAB * 4}  xmlns="http://datacite.org/schema/kernel-4"
          #{TAB * 4}  xsi:schemaLocation="http://datacite.org/schema/kernel-4 http://schema.datacite.org/meta/kernel-4.4/metadata.xsd">
          #{TAB * 2}<identifier identifierType="DOI">#{dmp_id.match(Uc3DmpId::Helper::DOI_REGEX)}</identifier>
          #{TAB * 2}<creators>
          #{person_to_xml(json: dmp['contact'], tab_count: 3)}#{TAB * 2}</creators>
          #{TAB * 2}<titles>
          #{TAB * 3}<title xml:lang="en-US">#{percent_encode(val: dmp['title'])}</title>
          #{TAB * 2}</titles>
          #{TAB * 2}<publisher xml:lang="en-US">#{APPLICATION_NAME}</publisher>
          #{TAB * 2}<publicationYear>#{Time.now.year}</publicationYear>
          #{TAB * 2}<language>#{two_char_language(val: dmp['language'])}</language>
          #{TAB * 2}<resourceType resourceTypeGeneral="OutputManagementPlan">#{DEFAULT_RESOURCE_TYPE}</resourceType>
          #{TAB * 2}<descriptions>
          #{TAB * 3}<description xml:lang="#{two_char_language(val: dmp['language'])}" descriptionType="Abstract">
          #{TAB * 4}#{percent_encode(val: dmp['description'])}
          #{TAB * 3}</description>
          #{TAB * 2}</descriptions>
        XML

        unless contributors.empty?
          xml += <<~XML
            #{TAB * 2}<contributors>
          XML
          contributors.compact.each { |c| xml += person_to_xml(json: c[:json], type: c[:type], tab_count: 3) }
          xml += <<~XML
            #{TAB * 2}</contributors>
          XML
        end
        unless fundings.compact.empty?
          xml += <<~XML
            #{TAB * 2}<fundingReferences>
          XML
          fundings.each { |fund| xml += funding_to_xml(json: fund, tab_count: 3) }
          xml += <<~XML
            #{TAB * 2}</fundingReferences>
          XML
        end
        unless dmp.fetch('dmproadmap_related_identifiers', []).empty?
          xml += <<~XML
            #{TAB * 2}<relatedIdentifiers>
          XML
          dmp['dmproadmap_related_identifiers'].each { |id| xml += related_id_to_xml(json: id, tab_count: 3) }
          xml += <<~XML
            #{TAB * 2}</relatedIdentifiers>
          XML
        end

        xml += <<~XML
          #{TAB}</resource>
        XML
        xml
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Convert a JSON representation of a Contact/Contributor for EZID
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def person_to_xml(json:, type: 'ProjectLeader', tab_count: 0)
        return '' unless json.is_a?(Hash)

        identifier = json['contact_id'] || json['contributor_id'] || json['affiliation_id'] ||
                     json['facility_id']

        name_type = 'Organizational' unless json['affiliation_id'].nil? && json['facility'].nil?
        name_type = 'Personal' if name_type.nil?

        name = name_type == 'Organizational' ? json['name'].to_s.gsub(/\(.*\)\s?$/, '').strip : json['name']

        tabs = tab_count.positive? ? (TAB * tab_count) : ''
        if json['contact_id'].nil?
          xml = <<~XML
            #{tabs}<contributor contributorType="#{type}">
            #{tabs}#{TAB}<contributorName nameType="#{name_type}">#{percent_encode(val: name)}</contributorName>
          XML

          xml += identifier_to_xml(json: identifier, type: 'name', tab_count: tab_count + 1) unless identifier.nil?
          unless json['dmproadmap_affiliation'].nil?
            xml += affiliation_to_xml(json: json['dmproadmap_affiliation'], tab_count: tab_count + 1)
          end

          xml += <<~XML
            #{tabs}</contributor>
          XML
        else
          xml = <<~XML
            #{tabs}<creator>
            #{tabs}#{TAB}<creatorName nameType="#{name_type}">#{percent_encode(val: name)}</creatorName>
          XML

          xml += identifier_to_xml(json: identifier, type: 'name', tab_count: tab_count + 1) unless identifier.nil?
          unless json['dmproadmap_affiliation'].nil?
            xml += affiliation_to_xml(json: json['dmproadmap_affiliation'], tab_count: tab_count + 1)
          end

          xml += <<~XML
            #{tabs}</creator>
          XML
        end
        xml
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Convert a JSON representation of an Affiliation for EZID
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def affiliation_to_xml(json:, tab_count: 0)
        return '' unless json.is_a?(Hash) &&
                         (!json['name'].nil? || !json.fetch('affiliation_id', {})['identifier'].nil?)

        identifier = json.fetch('affiliation_id', {})
        scheme_uri = SCHEMES[:"#{identifier['type']}"]
        scheme_type = identifier_type(json: identifier)

        name = json['name'].to_s.gsub(/\(.*\)\s?$/, '').strip unless json['name'].nil?
        name = identifier['identifier'] if name.nil?

        tabs = tab_count.positive? ? (TAB * tab_count) : ''
        if scheme_uri.nil?
          <<~XML
            #{tabs}<affiliation>#{percent_encode(val: name)}</affiliation>
          XML
        else
          <<~XML
            #{tabs}<affiliation affiliationIdentifier="#{identifier['identifier']}" affiliationIdentifierScheme="#{scheme_type}">
            #{tabs}#{TAB}#{percent_encode(val: name)}
            #{tabs}</affiliation>
          XML
        end
      end
      # rubocop:enable Metrics/AbcSize

      # Convert a JSON representation of an Identifier for EZID
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def identifier_to_xml(json:, type: 'name', tab_count: 0)
        return '' unless json.is_a?(Hash) && !json['identifier'].nil?

        scheme_uri = SCHEMES[:"#{json['type']}"]
        scheme_type = identifier_type(json:)

        tabs = tab_count.positive? ? (TAB * tab_count) : ''
        if scheme_uri.nil?
          id = json['identifier']
          id = "#{DOI_URL}/#{id}" if scheme_type == 'DOI' && !id.start_with?('http')
          id = "http://#{id}" if scheme_type == 'URL' && !id.start_with?('http')
          <<~XML
            #{tabs}<#{type}Identifier>#{id}</#{type}Identifier>
          XML
        else
          <<~XML
            #{tabs}<#{type}Identifier schemeURI="#{scheme_uri}" #{type}IdentifierScheme="#{scheme_type}">
            #{tabs}#{TAB}#{json['identifier']}
            #{tabs}</#{type}Identifier>
          XML
        end
      end
      # rubocop:enable Metrics/AbcSize

      # Convert a Funding into a DataCite Funding Reference
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def funding_to_xml(json:, tab_count: 0)
        return '' unless json.is_a?(Hash)

        tabs = tab_count.positive? ? (TAB * tab_count) : ''
        xml = <<~XML
          #{tabs}<fundingReference>
          #{tabs}#{TAB}<funderName>#{percent_encode(val: json[:name])}</funderName>
        XML

        unless json[:identifier].nil?
          scheme_type = json[:type] == 'ror' ? 'ROR' : 'Crossref Funder ID'
          xml += <<~XML
            #{tabs}#{TAB}<funderIdentifier funderIdentifierType="#{scheme_type}">#{json[:identifier]}</funderIdentifier>
          XML
        end

        unless json[:grant].nil?
          xml += <<~XML
            #{tabs}#{TAB}<awardNumber #{json[:grant].start_with?('http') ? "awardURI=\"#{json[:grant]}\">" : '>'}#{json[:grant]}</awardNumber>
            #{tabs}#{TAB}<awardTitle>#{percent_encode(val: json[:title])}</awardTitle>
          XML
        end

        xml += <<~XML
          #{tabs}</fundingReference>
        XML
        xml
      end
      # rubocop:enable Metrics/AbcSize

      # Convert a Related Idenitfier into a DataCite Related Identifier
      # --------------------------------------------------------------------------------
      def related_id_to_xml(json:, tab_count: 0)
        return '' unless json.is_a?(Hash)

        descriptor = 'References' if json['descriptor'].nil?
        descriptor = json['descriptor'].to_s.split('_').map(&:capitalize).join if descriptor.nil?

        tabs = tab_count.positive? ? (TAB * tab_count) : ''
        <<~XML
          #{tabs}<relatedIdentifier relationType="#{descriptor}" relatedIdentifierType="#{identifier_type(json:)}">
          #{tabs}#{TAB}#{json['identifier']}
          #{tabs}</relatedIdentifier>
        XML
      end

      # Determine the identifier type based on the specified :type and :identifier value
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize
      def identifier_type(json:)
        return 'URL' unless json.is_a?(Hash)

        scheme_uri = SCHEMES[:"#{json['type']}"]
        scheme_type = json['type'].upcase unless scheme_uri.nil?

        id = json['identifier'].to_s.gsub(%r{https?://}, '')
                               .gsub(Uc3DmpId::Helper.dmp_id_base_url.gsub(%r{https?://}, ''), '')
        id = id[1..id.length] if id.start_with?('/')

        scheme_type = 'DOI' if scheme_type.nil? &&
                               !id.match(Uc3DmpId::Helper::DOI_REGEX).nil? &&
                               id.match(Uc3DmpId::Helper::DOI_REGEX).to_s.strip != ''

        scheme_type = 'URL' if scheme_type.nil? &&
                               !json['identifier'].to_s.match(Uc3DmpId::Helper::URL_REGEX).nil? &&
                               json['identifier'].to_s.match(Uc3DmpId::Helper::URL_REGEX).to_s.strip != ''
        scheme_type
      end
      # rubocop:enable Metrics/AbcSize

      # EZID's ANVL parser requires percent encoding, so encode specific characters
      # --------------------------------------------------------------------------------
      def percent_encode(val:)
        # Ruby deprecated URI.escape, and CGI.escapeHTML doesn't do percent encoding which is
        # what EZID uses, so we need to do some manual encoding :/
        # 1st remove any HTML tags
        val = val.to_s.gsub(/<(?:"[^"]*"['"]*|'[^']*'['"]*|[^'">])+>/, '')
        # 2nd remove any newlines
        val = val.gsub('\u00A0', ' ')
        # 3rd percent encode any percent signs
        val = val.gsub('%', '%25')
        # 4th escape any HTML
        val = CGI.escapeHTML(val)
        # 5th remove unecessary whitespace
        val = val.gsub('  ', ' ') while val.include?('  ')
        val.strip
      end

      # Convert a NISO credit URI into a DataCite Contributor Role
      # --------------------------------------------------------------------------------
      def contributor_role(value:)
        case value
        when 'http://credit.niso.org/contributor-roles/data-curation'
          'DataCurator'
        when 'http://credit.niso.org/contributor-roles/formal-analysis',
            'http://credit.niso.org/contributor-roles/software',
            'http://credit.niso.org/contributor-roles/validation'
          'Researcher'
        when 'http://credit.niso.org/contributor-roles/investigation'
          'ProjectLeader'
        when 'http://credit.niso.org/contributor-roles/methodology'
          'DataManager'
        when 'http://credit.niso.org/contributor-roles/project-administration'
          'ProjectManager'
        when 'http://credit.niso.org/contributor-roles/supervision'
          'Supervisor'
        when 'http://credit.niso.org/contributor-roles/writing-review-editing'
          'Editor'
        else
          DEFAULT_CONTRIBUTOR_ROLE
        end
      end

      # Convert a 3 character language code that the RDA common standard requires into
      # a 2 character langauge code required by DataCite
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/MethodLength
      def two_char_language(val:)
        codes = {
          aar: 'aa', abk: 'ab', afr: 'af', aka: 'ak', amh: 'am', ara: 'ar', arg: 'an',
          asm: 'as', ava: 'av', ave: 'ae', aym: 'ay', aze: 'az',

          bak: 'ba', bam: 'bm', bel: 'be', ben: 'bn', bih: 'bh', bis: 'bi', tib: 'bo',
          bos: 'bs', bre: 'br', bul: 'bg',

          cat: 'ca', cze: 'cs', cha: 'ch', che: 'ce', chu: 'cu', chv: 'cv', cos: 'co',
          cre: 'cr', wel: 'cy',

          dan: 'da', deu: 'de', div: 'dv', dzo: 'dz',

          gre: 'el', eng: 'en', epo: 'eo', spa: 'es', est: 'et', baq: 'eu', ewe: 'ee',

          fao: 'fo', per: 'fa', fij: 'fj', fin: 'fi', fre: 'fr', fry: 'fy', ful: 'ff',

          gla: 'gd', dle: 'ga', glg: 'gl', glv: 'gv', grn: 'gn', guj: 'gu',

          hat: 'ht', hau: 'ha', heb: 'he', her: 'hz', hin: 'hi', hmo: 'ho', hrv: 'hr',
          hun: 'hu', arn: 'hy',

          ibo: 'ig', ido: 'io', iii: 'ii', iku: 'iu', ile: 'ie', ina: 'ia', ind: 'id',
          ipk: 'ik', ice: 'is', ita: 'it',

          jav: 'jv', jpn: 'ja',

          kal: 'kl', kan: 'kn', kas: 'ks', kau: 'kr', kaz: 'kk', khm: 'km', kik: 'ki',
          kir: 'ky', kom: 'kv', kon: 'kg', kor: 'ko', kua: 'kj', kur: 'ku', geo: 'ka', cor: 'kw',

          lao: 'lo', lat: 'la', lav: 'lv', lim: 'li', lin: 'ln', lit: 'lt', ltz: 'lb',
          lub: 'lu', lug: 'lg',

          mac: 'mk', mah: 'mh', mal: 'ml', mao: 'mi', mar: 'mr', may: 'ms', mlg: 'mg',
          mlt: 'mt', mon: 'mn', bur: 'my',

          nau: 'na', nav: 'nv', nbl: 'nr', nde: 'nd', ndo: 'ng', nep: 'ne', dut: 'nl',
          nno: 'nn', nob: 'nb', nor: 'no', nya: 'ny',

          oci: 'oc', oji: 'oj', ori: 'or', orm: 'om', oss: 'os',

          pan: 'pa', pli: 'pi', pol: 'pl', por: 'pt', pus: 'ps',

          que: 'qu',

          roh: 'rm', rum: 'ro', run: 'rn', rus: 'ru', kin: 'rw',

          sag: 'sg', san: 'sa', sin: 'si', slo: 'sk', slv: 'sl', sme: 'se', smo: 'sm',
          sna: 'sn', snd: 'sd', som: 'so', sot: 'st', alb: 'sq', srd: 'sc', srp: 'sr',
          ssw: 'ss', sun: 'su', swa: 'sw', swe: 'sv',

          tah: 'ty', tam: 'ta', tat: 'tt', tel: 'te', tgk: 'tg', tgl: 'tl', tha: 'th',
          tir: 'ti', ton: 'to', tsn: 'tn', tso: 'ts', tuk: 'tk', tur: 'tr', twi: 'tw',

          uig: 'ug', ukr: 'uk', urd: 'ur', uzb: 'uz',

          ven: 've', vie: 'vi', vol: 'vo',

          wln: 'wa', wol: 'wo',

          xho: 'xh',

          yid: 'yi', yor: 'yo',

          zha: 'za', chi: 'zh', zul: 'zu'
        }
        codes[:"#{val}"] || DEFAULT_LANGUAGE
      end
      # rubocop:enable Metrics/MethodLength
    end
  end
  # rubocop:enable Metrics/ClassLength
end
