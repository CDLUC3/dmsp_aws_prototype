# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'active_record'
require 'active_record_simple_execute'
require 'aws-sdk-sns'
require 'aws-sdk-ssm'
require 'mysql2'

require_relative 'lib/messages'
require_relative 'lib/responder'
require_relative 'lib/ssm_reader'

module Functions
  # The handler for POST /dmps/validate
  class GetFunders
    SOURCE = 'GET /funders?search=name'.freeze
    TABLE = 'registry_orgs'.freeze

    FUNDREF_URI_PREFIX = 'https://doi.org/10.13039/'.freeze

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
    #        "name": "National Institutes of Health (nih.gov)",
    #        "funder_id": {
    #          "identifier": "https://api.crossref.org/funders/100000002",
    #          "type": "fundref"
    #        },
    #        "funder_api": "api.dmphub-dev.cdlib.org/funders/100000002/api",
    #        "funder_api_label": "Project lookup",
    #        "funder_api_guidance": "Please enter your research project title"
    #      },
    #      {
    #        "name": "National Science Foundation (nsf.gov)",
    #        "funder_id": {
    #          "identifier": "https://api.crossref.org/funders/10000001",
    #          "type": "fundref"
    #        }
    #      }
    #    ]

    class << self
      # This is a temporary endpoint used to provide pseudo user data to the React application
      # while it is under development. This will eventually be replaced by Cognito or the Rails app.
      def process(event:, context:)
        params = event.fetch('queryStringParameters', {})
        # Only process if there are 3 or more characters in the search
        continue = !params['search'].nil? || params['search'].length >= 3
        return Responder.respond(status: 400, errors: [Messages::MSG_INVALID_ARGS], event: event) unless continue

        page = params.fetch('page', Responder::DEFAULT_PAGE)
        page = Responder::DEFAULT_PAGE if page <= 1
        per_page = params.fetch('per_page', Responder::DEFAULT_PER_PAGE)
        per_page = Responder::DEFAULT_PER_PAGE if per_page >= Responder::MAXIMUM_PER_PAGE || per_page <= 1

        # Debug, output the incoming Event and Context
        debug = SsmReader.debug_mode?
        pp event if debug
        pp context if debug

        rds_connect
        # return Responder.respond(status: 500, errors: [Messages::MSG_SERVER_ERROR], event: event) if NOT CONNECTED

        items = search(term: params['search'])
        return Responder.respond(status: 200, items: [], event: event) unless !items.nil? && items.length.positive?

        results = results_to_response(term: params['search'], results: items)
        Responder.respond(status: 200, items: results, event: event, page: page, per_page: per_page)
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
        { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
      rescue StandardError => e
        # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
        puts "#{SOURCE} FATAL: #{e.message}"
        puts e.backtrace
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end

      private

      # Run the search query against the DB and return the raw results
      def search(term:)
        sql_str = <<~SQL.squish
          SELECT * FROM registry_orgs
          WHERE registry_orgs.fundref_id IS NOT NULL AND
            (registry_orgs.name LIKE :term OR registry_orgs.home_page LIKE :term
              OR registry_orgs.acronyms LIKE :quoted_term OR registry_orgs.aliases LIKE :quoted_term)
        SQL
        ActiveRecord::Base.simple_execute(sql_str, term: "%#{term}%", quoted_term: "%\"#{term}\"%")
      end

      # Transform the raw DB response for the API caller
      def results_to_response(term:, results:)
        return [] if results.nil? || !results.is_a?(Array) || !term.is_a?(String)

        results = results.map do |funder|
          id = funder['fundref_id'] if funder['fundref_id'].start_with?(FUNDREF_URI_PREFIX)
          id = "#{FUNDREF_URI_PREFIX}#{funder['fundref_id']}" if id.nil?
          hash = {
            name: funder['name'],
            weight: weigh(term: term, org: funder),
            funder_id: { identifier: id, type: 'fundref' }
          }
          unless funder['api_target'].nil?
            hash[:funder_api] = "api.#{ENV['DOMAIN']}/funders/#{funder['fundref_id']}/api"
            hash[:funder_api_label] = funder['api_label']
            hash[:funder_api_guidance] = funder['api_guidance']
          end
          hash
        end
        results.sort { |a, b| [b[:weight], a[:name]] <=> [a[:weight], b[:name]] }
      end

      # Weighs the RegistryOrg. The greater the weight the closer the match, preferring Orgs already in use
      def weigh(term:, org:)
        score = 0
        return score unless term.is_a?(String) && org['name'].is_a?(String)

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

      # Connect to the RDS instance
      def rds_connect
        ActiveRecord::Base.establish_connection(
          adapter: 'mysql2',
          host: ENV["DATABASE_HOST"],
          port: ENV["DATABASE_PORT"],
          database: ENV["DATABASE_NAME"],
          username: SsmReader.get_ssm_value(key: SsmReader::RDS_USERNAME),
          password: SsmReader.get_ssm_value(key: SsmReader::RDS_PASSWORD),
          encoding: 'utf8mb4'
        )
      end
    end
  end
end
