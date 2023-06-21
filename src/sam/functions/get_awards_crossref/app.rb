# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-external-api'
require 'uc3-dmp-provenance'

module Functions
  # A Proxy service that queries the NSF Awards API and transforms the results into a common format
  class GetAwardsCrossref
    SOURCE = 'GET /awards/crossref'

    # Documentation can be found here: https://api.reporter.nih.gov
    API_BASE_URL = 'https://api.crossref.org/works'

    LANDING_BASE_URL = 'https://doi.org/'

    MSG_NO_FUNDER = 'You must specify the funder id as part of the path (e.g. /awards/crossref/10.13039/100000015)'
    MSG_BAD_ARGS = 'You must specify an award DOI (e.g. project=10.46936/cpcy.proj.2019.50733/60006578), /
                    PI names (e.g "pi_names=Jane Doe,Van Buren,John Smith"); a project title (e.g. title=); and /
                    applicable award years (optional) (e.g. years=2023,2021)'
    MSG_EMPTY_RESPONSE = 'Crossref API returned an empty resultset'

    def self.process(event:, context:)
      funder = event.fetch('pathParameters', {})['funder_id']
      return Responder.respond(status: 400, errors: MSG_NO_FUNDER) if funder.nil? || funder.empty?

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      puts event if debug
      puts context if debug

      params = event.fetch('queryStringParameters', {})
      pi_names = params.fetch('pi_names', '')
      project_num = params.fetch('project', '')
      title = params.fetch('keyword', '')
      years = params.fetch('years', (Date.today.year..Date.today.year - 3).to_a.join(','))
      years = years.split(',').map(&:to_i)
      return _respond(status: 400, errors: [MSG_BAD_ARGS], event: event) if (title.nil? || title.empty?) &&
                                                                            (pi_names.nil? || pi_names.empty?)

      url = "#{project_num}" unless project_num.nil? || project_num.empty?
      url = "?#{_prepare_query_string(funder: funder, pi_names: pi_names, title: title, years: years)}" if url.nil?
      url = "#{API_BASE_URL}#{url}"

      resp = Uc3DmpExternalApi::Client.call(url: url, method: :get, debug: true) # debug)
      if resp.nil? || resp.to_s.strip.empty?
        Uc3DmpApiCore::Responder.log_error(source: SOURCE, message: MSG_EMPTY_RESPONSE, details: resp)
        return _respond(status: 404, items: [], event: event)
      end

      results = _transform_response(response_body: resp)
      _respond(status: 200, items: results.compact.uniq, event: event, params: params)
    rescue Uc3DmpExternalApi::ExternalApiError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue Aws::Errors::ServiceError => e
      _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder.rb that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end

    private

    class << self
      # URI encode the values sent in
      def _sanitize_params(str:, params: {})
        return str if str.nil? || !params.is_a?(Hash)

        params.each do |k, v|
          val = v.to_s.strip.gsub(%r{\s}, '+')
          str = str.gsub(":#{k}", URI.encode_www_form_component(val))
        end
        str
      end

      # Prepare the query string for the API call
      def _prepare_query_string(funder:, pi_names: [], title: '', years: [])
        return '' if funder.nil?

        qs = ['sort=score']
        years = years.map(&:to_s).reject { |yr| yr.length != 4 }.sort if years.is_a?(Array)

        words = title.nil? ? '' : title.tr('+', ' ')
        words += pi_names.split(',').map { |name| name.tr('+', ' ') }.join(' ')
        qs << _sanitize_params(str: 'query=:words', params: { words: words }) unless words.nil? || words.empty?
        qs << "filter=type:grant,funder:#{funder}"
        qs = qs.join('&')
        return qs if years.empty?

        filter_params = {
          start: "#{years.first}-01-01",
          end: "#{years.last}-12-31"
        }
        qs += _sanitize_params(str: ",from-awarded-date::start,until-awarded-date::end", params: filter_params)
      end

      # Convert the PI info from the response into "Last, First"
      def _pi_from_response(pi_hash:)
        pi = { name: [pi_hash['family'], pi_hash['given']].compact.join(', ') }
        affiliation = pi_hash.fetch('affiliation', []).first
        return pi if affiliation.nil?

        id = affiliation.fetch('id', []).first
        unless id.nil?

puts id
puts id.class.name
puts id['id-type']
puts id['id']

          affiliation_id = { identifier: id['id'], type: 'ror' } if !id.nil? &&
                                                                    id['id-type']&.downcase&.strip == 'ror'

puts affiliation_id

        end
        affil = { name: affiliation['name'] }
        affil['affiliation_id'] = affiliation_id unless affiliation_id.nil?
        pi[:dmproadmap_affiliation] = affil
        pi
      end

      # Transform the NSF API results into our common funder API response
      #
      # Expected format (note that direct search for an award does not include 'items' array:
      # {
      #   message: {
      #     items: [
      #       {
      #         indexed: {
      #           date-parts: [[2022,4,2]],
      #           date-time: "2022-04-02T11:36:52Z",
      #           timestamp: 1648899412241
      #         },
      #         publisher: "Office of Scientific and Technical Information (OSTI)",
      #         award-start: {
      #           date-parts: [[2020,10,12]]
      #         },
      #         award: "51740",
      #         DOI: "10.46936\/cpcy.proj.2020.51740\/60000288",
      #         type: "grant",
      #         created: {
      #           date-parts: [[2021,8,19]],
      #           date-time: "2021-08-19T19:40:12Z",
      #           timestamp: 1629402012000
      #         },
      #         source: "Crossref",
      #         prefix: "10.46936",
      #         member: "960",
      #         project: [
      #           {
      #             project-title: [
      #               {
      #                 title: "CT imaging of Rugged Particle Tracers"
      #               }
      #             ],
      #             lead-investigator: [
      #               {
      #                 given: "Lance",
      #                 family: "Hubbard",
      #                 affiliation: []
      #               }
      #             ],
      #             funding: [
      #               {
      #                 type: "award",
      #                 funder: {
      #                   name: "US Department of Energy",
      #                   id: [
      #                     {
      #                       id: "10.13039\/100000015",
      #                       id-type: "DOI",
      #                       asserted-by: "publisher"
      #                     }
      #                   ]
      #                 }
      #               }
      #             ]
      #           }
      #         ],
      #         deposited: {
      #           date-parts: [[2021,10,8]],
      #           date-time: "2021-10-08T21:20:46Z",
      #           timestamp: 1633728046000
      #         },
      #         score: 7.88397,
      #         resource: {
      #           primary: {
      #             URL: "https:\/\/www.osti.gov\/award-doi-service\/biblio\/10.46936\/cpcy.proj.2020.51740\/60000288"
      #           }
      #         },
      #         issued: {
      #           date-parts: [[2020,10,12]]
      #         },
      #         URL: "http:\/\/dx.doi.org\/10.46936\/cpcy.proj.2020.51740\/60000288"
      #       }
      #     ]
      #   }
      # }
      def _transform_response(response_body:)
        return [] unless response_body.is_a?(Hash)
        return [] if response_body['message'].nil?

        items = response_body['message'].fetch('items', [response_body['message']])

        items.map do |item|
          project = item.fetch('project', []).first
          next if project.nil? || project.fetch('project-title', []).first.nil? ||
                  project.fetch('lead-investigator', []).first.nil? ||
                  project.fetch('funding', []).first.nil?

          award_start = item.fetch('award-start', project.fetch('award-start', {}))['date-parts']&.first&.join('-')
          award_end = item.fetch('award-end', project.fetch('award-end', {}))['date-parts']&.first&.join('-')

          {
            project: {
              title: project.fetch('project-title', []).first['title'],
              description: item.fetch('abstract', project['project-description']&.first),
              start: award_start,
              end: award_end,
              funding: [
                dmproadmap_project_number: item['award'],
                dmproadmap_award_amount: project.fetch('award-amount', {})['amount'],
                grant_id: {
                  identifier: item['URL'].gsub('\/', '/'),
                  type: 'url'
                }
              ]
            },
            contact: _pi_from_response(pi_hash: project['lead-investigator'].first),
            contributor: project.fetch('investigator', []).map { |contrib| _pi_from_response(pi_hash: contrib) }
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