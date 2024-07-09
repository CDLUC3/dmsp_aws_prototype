# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'

module Functions
  # The handler for: GET /dmps
  #
  # Search criteria expects at least one of the following in the QueryString
  #   An owner
  #    owner    - The :contact ORCID or email (e.g. `?owner=0000-0000-0000-000X` or `?owner=foo%40example.com`)
  #    org      - The :contact :affiliation ROR (e.g. `?org=8737548t`)
  #    funder   - The :project :funder_id ROR (e.g. `?funder=12345abc`)
  #    featured - The date of the modification (e.g. `?featured=true`)
  #
  # The caller can also specify pagination params for :page and :per_page
  class GetDmps
    SOURCE = 'GET /dmps'

    MSG_INVALID_SEARCH = 'Invalid search criteria. Please specify at least one of the following: \
                          [`?owner=0000-0000-0000-0000`, `?owner=test%40example.com`, \
                           `?org=8737548t`, `?funder=12345abc`, `featured=true`]'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

      params = _process_params(event:)
      _set_env(logger:)
      logger&.info(message: "DMP ID Search Criteria: #{params}")

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger:)
      return _respond(status: 403, errors: Uc3DmpId::Helper::MSG_DMP_FORBIDDEN, event:) if provenance.nil?

      # resp = Uc3DmpId::Finder.search_dmps(args: params, logger:)
      client = Uc3DmpDynamo::Client.new(table: ENV['DYNAMO_INDEX_TABLE'])
      resp = _find_by_orcid(client:, owner: params['owner'], logger:)
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID) if resp.nil?
      return _respond(status: 404, errors: Uc3DmpId::Helper::MSG_DMP_NOT_FOUND) if resp.empty?

      logger.debug(message: 'Found the following results:', details: resp) if logger.respond_to?(:debug)
      _respond(status: 200, items: [resp], event:)
    rescue Uc3DmpId::FinderError => e
      _respond(status: 400, errors: [Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID, e.message], event:)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      deets = { message: e.message, params: }
      Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
      { statusCode: 500, body: { errors: [Uc3DmpId::Helper::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    class << self

      def _find_by_orcid(client:, owner:, logger: null)
        orcid_regex = /^([0-9A-Z]{4}-){3}[0-9A-Z]{4}$/
        orcid = owner.to_s.strip.downcase
        return [] if (orcid =~ orcid_regex).nil?

        client = Uc3DmpDynamo::Client.new if client.nil?
        resp = client.get_item(
          key: { PK: orcid, SK: 'ORCID_INDEX' },
          logger:
        )
        return resp unless resp.is_a?(Hash)
        logger&.debug(message: "DMPs for ORCID #{orcid}", details: resp)
        resp.fetch('dmps', []).any? ? _fetch_dmps : _fetch_dmps(client:, dmps: resp['dmps'], logger:)
      end

      def _fetch_dmps(client:, dmps:, logger: null)
        # Build the key condition expression dynamically
        pks = dmps.map.with_index { |_, idx| ":pk#{idx}" }.join(', ')
        key_condition_expression = "PK IN (#{pks}) AND SK = :sk"

        # Build the expression attribute values dynamically
        expression_attribute_values = {}
        pks.each_with_index do |pk, idx|
          expression_attribute_values[":pk#{idx}"] = pk
        end
        expression_attribute_values[':sk'] = 'VERSION#latest'
        response = client.query({ key_condition_expression:, expression_attribute_values: })
        response.respond_to?(:items) ? response.items.sort { |a, b| b['modified'] <=> a['modified'] } : response
      end

      # rubocop:disable Metrics/AbcSize
      def _process_params(event:)
        params = event.fetch('queryStringParameters', {})
        return params unless params.keys.any?

        numeric = /^\d+$/
        max_per_page = Uc3DmpApiCore::Paginator::MAXIMUM_PER_PAGE

        params['page'] = Uc3DmpApiCore::Paginator::DEFAULT_PAGE if params['page'].nil? ||
                                                                   (params['page'].to_s =~ numeric).nil? ||
                                                                   params['page'].to_i <= 0

        params['per_page'] = Uc3DmpApiCore::Paginator::DEFAULT_PER_PAGE if params['per_page'].nil? ||
                                                                           (params['per_page'].to_s =~ numeric).nil? ||
                                                                           params['per_page'].to_i <= 0 ||
                                                                           params['per_page'].to_i >= max_per_page
        params
      end
      # rubocop:enable Metrics/AbcSize

      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger:)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger:)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger:)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status:, items:, errors:, event:,
          page: params['page'], per_page: params['per_page']
        )
      end
    end
  end
end
