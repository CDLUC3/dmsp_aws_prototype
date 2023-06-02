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
  class GetRepositories
    SOURCE = 'GET /repositories?search=name'
    TABLE = 'repositories'

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
    #        "title": "Dryad",
    #        "description": "Dryad is an international repository of data …",
    #        "url": "https://datadryad.org",
    #        "dmproadmap_host_id": {
    #          "identifier": "https://www.re3data.org/repository/r3d100000044",
    #          "type": "url"
    #        }
    #      },
    #      {
    #        "title": "Zenodo",
    #        "description": "ZENODO builds and operates a simple and innovative service …",
    #        "url": "https://zenodo.org",
    #        "dmproadmap_host_id": {
    #          "identifier": "https://www.re3data.org/repository/r3d100010468",
    #          "type": "url"
    #        }
    #      },
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

        principal = event.fetch('requestContext', {}).fetch('authorizer', {})
        return _respond(status: 401, errors: [Uc3DmpRds::MSG_MISSING_USER], event: event) if principal.nil? ||
                                                                                             principal['mbox'].nil?

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
        { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Run the search query against the DB and return the raw results
      def _search(term:)
        sql_str = <<~SQL.squish
          SELECT * FROM repositories
          WHERE repositories.name LIKE :term OR repositories.homepage LIKE :term
              OR repositories.description LIKE :term
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, term: "%#{term}%")
      end

      # Transform the raw DB response for the API caller
      # rubocop:disable Metrics/AbcSize
      def _results_to_response(term:, results:)
        return [] unless results.is_a?(Array) && term.is_a?(String) && !term.strip.empty?

        results = results.map do |repo|
          hash = {
            title: repo['name'],
            description: repo['description'],
            url: repo['homepage'],
            weight: _weigh(term: term, repo: repo)
          }
          hash[:dmproadmap_host_id] = { identifier: repo['uri'], type: 'url' } unless repo['uri'].nil?
          hash
        end
        results.sort { |a, b| [b[:weight], a[:title]] <=> [a[:weight], b[:title]] }
      end
      # rubocop:enable Metrics/AbcSize

      # Weighs the Repository. The greater the weight the closer the match
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def _weigh(term:, repo:)
        score = 0
        return score unless term.is_a?(String) && repo.is_a?(Hash) && repo['name'].is_a?(String)

        term = term.downcase
        name = repo['name'].downcase
        descr_match = repo['description']&.downcase&.include?(term)
        url_match = repo['homepage']&.downcase&.include?(term)
        starts_with = name.start_with?(term)

        # Scoring rules explained:
        # 1 - Description match
        # 1 - Homepage match
        # 2 - Repository.starts with term
        # 1 - :name includes term
        score += 1 if descr_match
        score += 1 if url_match
        score += 2 if starts_with
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
