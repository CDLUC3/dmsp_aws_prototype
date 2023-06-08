# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'

module Functions
  # The lambda handler for: POST /dmps
  class PostDmps
    SOURCE = 'POST /dmps'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      body = event.fetch('body', '')

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      puts event if debug
      puts context.inspect if debug
      puts body if debug

      return _respond(status: 400, errors: Uc3DmpId::Validator::MSG_EMPTY_JSON, event: event) if body.to_s.strip.empty?
      json = Uc3DmpId::Helper.parse_json(json: body)

      _set_env

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim)
      return _respond(status: 403, errors: Uc3DmpId::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

puts "PROVENANCE:"
puts provenance
puts "BODY:"
puts json
puts "OWNER ORG:"
puts _extract_org(json: json)

      # Get the DMP
      resp = Uc3DmpId::Creator.create(provenance: provenance, owner_org: _extract_org(json: json), json: json, debug: debug)
      return _respond(status: 400, errors: Uc3DmpId::MSG_DMP_NO_DMP_ID) if resp.nil?

      _respond(status: 201, items: rep, event: event)
    rescue Uc3DmpId::CreatorError => e
      _respond(status: 400, errors: [Uc3DmpId::MSG_DMP_NO_DMP_ID, e.message], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    class << self

      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL']&.split('/')&.last
        ENV['DYNAMO_TABLE'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dynamo_table_name)
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url)
      end

      # Detemrine who the owner Organization/Institution is based on the contact and contributors
      def _extract_org(json:)
        return nil if json['dmp']['contact'].nil? && json['dmp'].fetch('contributor', []).empty?

        id = _affiliation_id_from_person(hash: json['dmp']['contact'])
        return id unless id.nil?

        orgs = json['dmp'].fetch('contributor').map { |contributor| _affiliation_id_from_person(hash: contributor) }
        orgs.max_by { |i| orgs.count(i) }
      end

      # Fetch the ROR from the contact/contributor hash
      def _affiliation_id_from_person(hash:)
        return nil unless hash.is_a?(Hash) && !hash.fetch('dmproadmap_affiliation', {})['affiliation_id'].nil?

        id_hash = hash['dmproadmap_affiliation'].fetch('affiliation_id', {})
        return nil if id_hash.fetch('identifier', '').to_s.strip.empty?

        id = id_hash['identifier'].to_s.downcase.strip
        id_hash['type'].to_s.downcase.strip == 'ror' ? id : nil
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
end
