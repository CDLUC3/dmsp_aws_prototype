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
    MSG_EMPTY_RESPONSE = 'NIH API returned an empty resultset'

    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event: event, level: log_level)

      params = _parse_params(event: event)
      continue = params[:project_num].length.positive? || params[:pi_names].length.positive?
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) unless continue

      body = _prepare_data(
        years: params[:fiscal_years],
        pi_names: _prepare_pi_names_for_search(pi_names: params[:pi_names]),
        opportunity_nbrs: [params[:opportunity_nbr]],
        project_nums: [params[:project_num]]
      )

      logger.debug(message: "Calling NIH Award API: #{API_BASE_URL} with body:", details: body) if logger.respond_to?(:debug)
      resp = Uc3DmpExternalApi::Client.call(url: API_BASE_URL, method: :post, body: body, logger: logger)
      if resp.nil? || resp.to_s.strip.empty?
        logger.error(message: MSG_EMPTY_RESPONSE, details: resp)
        return _respond(status: 404, items: [], event: event)
      end

      logger.debug(message: 'Found the following results:', details: resp) if logger.respond_to?(:debug)
      results = _transform_response(response_body: resp)
      _respond(status: 200, items: results.compact.uniq, event: event, params: params)
    rescue Uc3DmpExternalApi::ExternalApiError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue Aws::Errors::ServiceError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace) unless logger.nil?
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

    private

    class << self
      # Parse the incoming query string arguments
      def _parse_params(event:)
        params = event.fetch('queryStringParameters', {})
        fiscal_years = params.fetch('years', (Date.today.year..Date.today.year - 3).to_a.join(','))
        {
          project_num: params.fetch('project', ''),
          opportunity_nbr: params.fetch('opportunity', ''),
          pi_names: params.fetch('pi_names', ''),
          title: params.fetch('keyword', ''),
          fiscal_years: fiscal_years.split(',').map(&:to_i)
        }
      end

      # Convert the provided PI names into API criteria
      def _prepare_pi_names_for_search(pi_names:)
        names = pi_names.split(',')
        names = names.map do |name|
          parts = name.split('+')
          parts.length <= 1 ? { any_name: parts[0] } : { last_name: parts[1], given_name: parts[0] }
        end
        names.compact.uniq
      end

      # Prepare the API payload
      def _prepare_data(years:, pi_names: [], opportunity_nbrs: [], project_nums: [])
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
      def _pi_from_response(hash:)
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
      def _transform_response(response_body:)
        return [] unless response_body.is_a?(Hash)

        response_body['results'].map do |result|
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
            contact: _pi_from_response(hash: contact_pi),
            contributor: other_pis.map { |pi_hash| _pi_from_response(hash: pi_hash) }
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