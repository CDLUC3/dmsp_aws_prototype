# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'httparty'
require 'uri'

require 'messages'
require 'responder'
require 'ssm_reader'

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

    def self.process(event:, context:)
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

      # begin
      #   response = HTTParty.get('http://checkip.amazonaws.com/')
      # rescue HTTParty::Error => error
      #   puts error.inspect
      #   raise error
      # end
      params = event.fetch('queryStringParameters', {})
      pi_names = params.fetch('pi_names', '')
      project_num = params.fetch('project', '')
      title = params.fetch('keyword', '')
      years = params.fetch('years', (Date.today.year..Date.today.year - 3).to_a.join(','))
      years = years.split(',').map(&:to_i)
      return Responder.respond(status: 400, errors: MSG_BAD_ARGS) if (project_num.nil? || project_num.empty?) &&
                                                                     (pi_names.nil? || pi_names.empty?)

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      url = "#{API_BASE_URL.gsub('.json', "/#{project_num}.json")}" unless project_num.nil? || project_num.empty?
      url = "#{API_BASE_URL}?#{prepare_query_string(pi_names: pi_names, title: title, years: years)}" if url.nil?

puts url

      # TODO: Update the User-Agent to include the domain url and the admin email (from SSM)
      opts = {
        headers: {
          'Accept': 'application/json',
          'User-Agent': "DMPTool"
        },
        follow_redirects: true,
        limit: 6
      }
      opts[:debug_output] = $stdout # if debug

      resp = HTTParty.get(url, opts)
      if resp.body.nil? || resp.body.empty? || resp.code != 200
        Responder.log_error(source: SOURCE, message: "Error from NSF API: #{resp.code}", details: resp.body)
        return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
      end

      results = transform_response(response_body: resp.body)
      return Responder.respond(status: 404, items: []) unless results.any?

      Responder.respond(status: 200, items: results.compact.uniq)
    rescue URI::InvalidURIError
      Responder.log_error(source: SOURCE, message: "Invalid URI, #{API_BASE_URL}", details: e.backtrace)
      return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
    rescue HTTParty::Error => e
      Responder.log_error(source: SOURCE, message: "HTTParty error: #{e.message}", details: e.backtrace)
      return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
    rescue JSON::ParserError => e
      Responder.log_error(source: SOURCE, message: 'Error from NSF API JSON response!', details: resp&.body)
      return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      return Responder.respond(status: 500, errors: Messages::MSG_SERVER_ERROR, event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
    end

    private

    class << self
      # URI encode the values sent in
      def sanitize_params(str:, params: {})
        return str if str.nil? || !params.is_a?(Hash)

        params.each { |k, v| str = str.gsub(":#{k}", URI.encode_www_form_component(v.to_s.strip)) }
        str
      end

      # Prepare the query string for the API call
      def prepare_query_string(pi_names: [], title: '', years: [])
        qs = []
        years = years.map(&:to_s).reject { |yr| yr.length != 4 }.sort if years.is_a?(Array)
        pi_name = pi_names.split(',').first&.to_s&.strip&.gsub(%r{\s}, '+') unless pi_names.is_a?(Array)

        qs << sanitize_params(str: 'keyword=:title', params: { title: title }) unless title.to_s.strip.empty?
        qs << sanitize_params(str: 'pdPIName=:name', params: { name: pi_name }) unless pi_name.to_s.strip.empty?
        return qs.join('&') if years.empty?

        start_date = "01/01/#{years.first}"
        end_date = "12/31/#{years.last}"
        qs << sanitize_params(str: 'dateStart=:start', params: { start: start_date }) unless years.first.nil?
        qs << sanitize_params(str: 'dateEnd=:end', params: { end: end_date }) unless years.last.nil?
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
      def transform_response(response_body:)
        json = JSON.parse(response_body)
        json.fetch('response', {}).fetch('award', []).map do |award|
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
    end
  end
end