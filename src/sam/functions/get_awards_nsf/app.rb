# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-external-api'
require 'uc3-dmp-provenance'

module Functions
  # A Proxy service that queries the NSF Awards API and transforms the results into a common format
  class GetAwardsNsf
    SOURCE = 'GET /awards/nsf'

    # Documentation can be found here: https://api.reporter.nih.gov
    API_BASE_URL = 'https://api.nsf.gov/services/v1/awards.json'

    LANDING_BASE_URL = 'https://www.nsf.gov/awardsearch/showAward?AWD_ID=:id&HistoricalAwards=false'

    MSG_BAD_ARGS = 'You must specify an award id (e.g. project=2223141) OR a comma separated list of:
                    PI names (e.g "pi_names=Jane Doe,Van Buren,John Smith"); /
                    title keywords (optional) (e.g. keyword=genetic); and /
                    applicable award years (optional) (e.g. years=2023,2021)'
    MSG_EMPTY_RESPONSE = 'NSF API returned an empty resultset'

    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      params = event.fetch('queryStringParameters', {})
      request_id = context.aws_request_id if context.is_a?(LambdaContext)
      pi_names = params.fetch('pi_names', '')
      project_num = params.fetch('project', '')
      title = params.fetch('keywords', '')
      years = params.fetch('years', (Date.today.year..Date.today.year - 3).to_a.join(','))
      years = years.split(',').map(&:to_i)
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) if (project_num.nil? || project_num.empty?) &&
                                                                            (years.nil? || years.empty?)


      url = "#{API_BASE_URL.gsub('.json', "/#{project_num}.json")}" unless project_num.nil? || project_num.empty?
      url = "#{API_BASE_URL}?#{_prepare_query_string(pi_names: pi_names, title: title, years: years)}" if url.nil?

      logger.info(message: "Calling NSF Api: #{url}") if logger.respond_to?(:debug) if logger.respond_to?(:debug)
      resp = Uc3DmpExternalApi::Client.call(url: url, method: :get, logger: logger)
      if resp.nil? || resp.to_s.strip.empty?
        logger.error(message: MSG_EMPTY_RESPONSE, details: resp)
        return _respond(status: 404, items: [], event: event)
      end

      logger.debug(message: 'Found the following results:', details: resp) if logger.respond_to?(:debug)
      results = _transform_response(response_body: resp)
      _respond(status: 200, items: results.compact.uniq, event: event, params: params)
    rescue Uc3DmpExternalApi::ExternalApiError => e
      logger.error(message: e.message, details: e.backtrace)
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue Aws::Errors::ServiceError => e
      logger.error(message: e.message, details: e.backtrace)
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

    private

    class << self
      # URI encode the values sent in
      def _sanitize_params(str:, params: {})
        return str if str.nil? || !params.is_a?(Hash)

        params.each { |k, v| str = str.gsub(":#{k}", URI.encode_www_form_component(v.to_s.strip)) }
        str
      end

      # Prepare the query string for the API call
      def _prepare_query_string(pi_names: [], title: '', years: [])

puts "QS PREP - pi_names: '#{pi_names}', title: '#{title}', years: '#{years}'"

        qs = []
        years = years.map(&:to_s).reject { |yr| yr.length != 4 }.sort if years.is_a?(Array)
        pi_name = pi_names.split(',').first&.to_s&.strip&.gsub(%r{\s}, '+') unless pi_names.is_a?(Array)

        qs << _sanitize_params(str: 'keyword=:title', params: { title: title }) unless title.to_s.strip.empty?
        qs << _sanitize_params(str: 'pdPIName=:name', params: { name: pi_name }) unless pi_name.to_s.strip.empty?

puts qs.join('&')

        return qs.join('&') if years.empty?

        start_date = "01/01/#{years.first}"
        end_date = "12/31/#{years.last}"
        qs << _sanitize_params(str: 'dateStart=:start', params: { start: start_date }) unless years.first.nil?
        qs << _sanitize_params(str: 'dateEnd=:end', params: { end: end_date }) unless years.last.nil?

puts qs.join('&')

        qs.join('&')
      end

      # Transform the NSF API results into our common funder API response
      #
      # Expected format:
      # {
      #   "response" : {
      #     "award" : [
      #       {
      #         "agency" : "NSF",
      #         "awardeeCity" : "WOODS HOLE",
      #         "awardeeName" : "Woods Hole Oceanographic Institution",
      #         "awardeeStateCode" : "MA",
      #         "fundsObligatedAmt" : "255244",
      #         "id" : "2223141",
      #         "piFirstName" : "Peter",
      #         "piLastName" : "Wiebe",
      #         "publicAccessMandate" : "1",
      #         "date" : "08/10/2022",
      #         "title" : "The Continuous Plankton Recorder (CPR) Survey of the Plankton of the North Atlantic"
      #       }
      #     ]
      #   }
      # }
      def _transform_response(response_body:)
        return [] unless response_body.is_a?(Hash)

        response_body.fetch('response', {}).fetch('award', []).map do |award|
          next if award['title'].nil? || award['id'].nil? || award['piLastName'].nil?

          {
            project: {
              title: award['title'],
              start: award.fetch('date', '').split('/').reverse.join('-'),
              funding: [
                dmproadmap_award_amount: award['fundsObligatedAmt'],
                dmproadmap_project_number: award['id'],
                grant_id: {
                  identifier: LANDING_BASE_URL.gsub(':id', award['id']),
                  type: 'url'
                }
              ]
            },
            contact: {
              name: [award['piLastName'], award['piFirstName']].join(', ')
            }
          }
        end
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