# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-rds'

module Functions
  # The handler for POST /dmps/validate
  class GetOrgs
    SOURCE = 'GET /orgs?search=name'
    TABLE = 'registry_orgs'

    ROR_URI_PREFIX = 'https://ror.org/'

    # Parameters
    # ----------
    # event: Hash, required
    #     API Gateway Lambda Proxy Input Format
    #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

    # Returns
    # ------
    # API Gateway Lambda Proxy Output Format: dict
    #     'statusCode' and 'body' are required
    #     # api-gateway-simple-proxy-for-lambda-output-format
    #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html

    # Example body:
    #    [
    #      {
    #        "name": "California Digitial Library (cdlib.org)",
    #        "affiliation_id": {
    #          "identifier": "https://ror.org/03yrm5c26",
    #          "type": "ror"
    #        }
    #      },
    #      {
    #        "name": "University of Washington (washington.edu)",
    #        "funder_id": {
    #          "identifier": "https://ror.org/00cvxb145",
    #          "type": "ror"
    #        }
    #      }
    #    ]

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      # rubocop:disable Metrics/AbcSize
      def process(event:, context:)
        params = event.fetch('queryStringParameters', {})
        # Only process if there are 3 or more characters in the search
        continue = params.fetch('search', '').to_s.strip.length >= 3
        return _respond(status: 400, errors: [Uc3DmpApiCore::MSG_INVALID_ARGS], event: event) unless continue

        # Debug, output the incoming Event and Context
        debug = Uc3DmpApiCore::SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        # Connect to the DB
        connected = _establish_connection
        return _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event) unless connected

        # Query the DB
        items = _search(term: params['search'])
        return _respond(status: 200, items: [], event: event) unless !items.nil? && items.length.positive?

        # Process the results
        results = _results_to_response(term: params['search'], results: items)
        _respond(status: 200, items: results, event: event, params: params)
      rescue Aws::Errors::ServiceError => e
        Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Run the search query against the DB and return the raw results
      def _search(term:)
        sql_str = <<~SQL.squish
          SELECT * FROM registry_orgs
          WHERE registry_orgs.ror_id IS NOT NULL AND
            (registry_orgs.name LIKE :term OR registry_orgs.home_page LIKE :term
              OR registry_orgs.acronyms LIKE :quoted_term OR registry_orgs.aliases LIKE :quoted_term)
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, term: "%#{term}%", quoted_term: "%\"#{term}\"%")
      end

      # Transform the raw DB response for the API caller
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def _results_to_response(term:, results:)
        return [] if results.nil? || !results.is_a?(Array) || !term.is_a?(String) || term.split.empty?

        results = results.map do |org|
          id = org['ror_id'] if org['ror_id']&.start_with?(ROR_URI_PREFIX)
          id = "#{ROR_URI_PREFIX}#{org['ror_id']}" if id.nil? && !org['ror_id'].nil?
          hash = {
            name: org['name'],
            weight: _weigh(term: term, org: org)
          }
          hash[:affiliation_id] = { identifier: id, type: 'ror' } unless id.nil?
          hash
        end
        results.sort { |a, b| [b[:weight], a[:name]] <=> [a[:weight], b[:name]] }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Weighs the RegistryOrg. The greater the weight the closer the match, preferring Orgs already in use
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def _weigh(term:, org:)
        score = 0
        return score unless term.is_a?(String) && org.is_a?(Hash) && org['name'].is_a?(String)

        term = term.downcase
        name = org['name'].downcase
        acronym_match = org['acronyms']&.downcase&.include?(term)
        alias_match = org['aliases']&.downcase&.include?(term)
        starts_with = name.start_with?(term)

        # Scoring rules explained:
        # 1 - Acronym match
        # 1 - Alias match
        # 2 - RegistryOrg.starts with term
        # 1 - RegistryOrg.org_id is not nil (meaning we've used it before)
        # 1 - :name includes term
        score += 1 if acronym_match
        score += 1 if alias_match
        score += 2 if starts_with
        score += 1 unless org['org_id'].nil?
        score += 1 if name.include?(term) && !starts_with
        score
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      def _establish_connection
        # Fetch the DB credentials from SSM parameter store
        username = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_username)
        password = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_password)
        Uc3DmpRds::Adapter.connect(username: username, password: password)
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
