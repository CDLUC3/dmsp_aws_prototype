# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'httparty'

require 'messages'
require 'responder'
require 'ssm_reader'

module Functions
  # A Proxy service that queries the NIH Awards API and transforms the results into a common format
  class GetAwardsNih
    SOURCE = 'GET /awards/nih'

    # Documentation can be found here: https://api.reporter.nih.gov
    API_BASE_URL = 'https://api.reporter.nih.gov/v2/projects/search'

    LANDING_BASE_URL = 'https://reporter.nih.gov/project-details/'

    MSG_BAD_ARGS = 'You must specify a project id (e.g. project=12345) OR a comma separate list of:
                    PI names (e.g "pi_names=Jane Doe,Van Buren,John Smith"); /
                    title keywords (optional) (e.g. keyword=genetic); /
                    a funding opportunity number (optional) (e.g. "opportunity=PA-18-484") and /
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

      # Expecting the queryStringParameters to include the following:
      #
      #   project=5R01AI143730-04                        <-- NIH Project number
      #
      #         OR
      #
      #   opportunity=PA-18-484&pi_names=Jane+Doe        <-- NIH opportunity nbr and PI names
      #
      #         OR
      #
      #   years=2023,2022&pi_names=Van+Buren,John+Smith  <-- Years and PI names
      #
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
      opportunity_nbr = params.fetch('opportunity', '')
      title = params.fetch('keyword', '')
      fiscal_years = params.fetch('years', (Date.today.year..Date.today.year - 3).to_a.join(','))
      fiscal_years = fiscal_years.split(',').map(&:to_i)
      return Responder.respond(status: 400, errors: MSG_BAD_ARGS) if (project_num.nil? || project_num.empty?) &&
                                                                     (pi_names.nil? || pi_names.empty?)

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # TODO: Update the User-Agent to include the domain url and the admin email (from SSM)

      opts = {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': "DMPTool"
        },
        body: prepare_data(
          years: fiscal_years,
          pi_names: prepare_pi_names_for_search(pi_names: pi_names),
          opportunity_nbrs: [opportunity_nbr],
          project_nums: [project_num]
        ),
        follow_redirects: true,
        limit: 6
      }
      opts[:debug_output] = $stdout if debug

      resp = HTTParty.post(API_BASE_URL, opts)
      if resp.body.nil? || resp.body.empty? || resp.code != 200
        Responder.log_error(source: SOURCE, message: "Error from NIH API: #{resp.code}", details: resp.body)
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
      Responder.log_error(source: SOURCE, message: 'Error from NIH API JSON response!', details: resp&.body)
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
      # Convert the provided PI names into API criteria
      def prepare_pi_names_for_search(pi_names:)
        names = pi_names.split(',')
        names = names.map do |name|
          parts = name.split('+')
          parts.length <= 1 ? { any_name: parts[0] } : { last_name: parts[1], given_name: parts[0] }
        end
        names.compact.uniq
      end

      # Prepare the API payload
      def prepare_data(years:, pi_names: [], opportunity_nbrs: [], project_nums: [])
        {
          criteria: {
            use_relevance: true,
            fiscal_years: years,
            pi_names: pi_names,
            foa: opportunity_nbrs,
            project_nums: project_nums
          },
          offset: 0,
          limit: 25
        }.to_json
      end

      # Convert the PI info from the response into "Last, First"
      def pi_from_response(hash:)
        if hash['last_name'].nil?
          full_name_parts = hash['full_name'].split(' ')
          nm = "#{full_name_parts.last}, #{full_name_parts[0..full_name_parts.length - 2].join(' ')}"
        else
          nm ="#{hash['last_name']}, #{[hash['first_name'], hash['middle_name']].join(' ')}"
        end

        { name: nm, mbox: hash['email'] }
      end

      # Transform the NIH API results into our common funder API response
      #
      # Expected format:
      # {
      #   "meta": {
      #     "total": 1,
      #     "offset": 0,
      #     "limit": 25,
      #     "sort_field": "project_start_date",
      #     "sort_order": "desc",
      #     "sorted_by_relevance": true,
      #   },
      #   "results": [
      #     {
      #       "appl_id": 10317069,
      #       "fiscal_year": 2022,
      #       "project_num": "5R01AI143730-04",
      #       "project_serial_num": "AI143730",
      #       "award_type": "5",
      #       "activity_code": "R01",
      #       "award_amount": 389299,
      #       "is_active": false,
      #       "principal_investigators": [
      #         {
      #           "profile_id": 1923056,
      #           "first_name": "Gerard",
      #           "middle_name": "C.",
      #           "last_name": "Wong",
      #           "is_contact_pi": true,
      #           "full_name": "Gerard C. Wong",
      #           "title": "",
      #           "email": null
      #         }
      #       ],
      #       "contact_pi_name": "WONG, GERARD C",
      #       "agency_ic_fundings": [
      #         {
      #           "fy": 2022,
      #           "code": "AI",
      #           "name": "National Institute of Allergy and Infectious Diseases",
      #           "abbreviation": "NIAID",
      #           "total_cost": 389299
      #         }
      #       ],
      #       "project_start_date": "2019-01-22T12:01:00Z",
      #       "project_end_date": "2023-12-31T12:12:00Z",
      #       "full_foa": "PA-18-484",
      #       "pref_terms": "Adenylate Cyclase;Behavior;Biology;Biomass;Biophysics;Cell Lineage;Cell surface;Cel...",
      #       "abstract_text": "PROJECT SUMMARY\nBiofilms are surface-attached microbial communities that ...",
      #       "project_title": "Surface sensing, memory, and motility control in biofilm formation",
      #       "agency_code": "NIH",
      #       "project_detail_url": null
      #     }
      #   ]
      # }
      def transform_response(response_body:)
        json = JSON.parse(response_body)
        json['results'].map do |result|
          next if result['project_title'].nil? || result['appl_id'].nil? || result['principal_investigators'].nil?

          contact_pi = result['principal_investigators'].select { |pi| pi['is_contact_pi'] }.first
          other_pis = result['principal_investigators'].reject { |pi| pi['is_contact_pi'] }

          {
            project: {
              title: result['project_title'],
              description: result['abstract_text'],
              start: result.fetch('project_start_date', '').split('T').first,
              end: result.fetch('project_end_date', '').split('T').first,
              funding: [
                dmproadmap_opportunity_number: result['full_foa'],
                dmproadmap_award_amount: result['award_amount'],
                dmproadmap_project_number: result['project_num'],
                grant_id: {
                  identifier: "#{LANDING_BASE_URL}#{result['appl_id']}",
                  type: 'url'
                }
              ]
            },
            contact: pi_from_response(hash: contact_pi),
            contributor: other_pis.map { |pi_hash| pi_from_response(hash: pi_hash) }
          }
        end
      end
    end
  end
end