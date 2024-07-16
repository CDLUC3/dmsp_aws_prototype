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
  #    featured - Return only plans marked as featured (e.g. `?featured=true`)
  #    search   - The term/phrase to search for in the Title and Abstract (e.g. `?search=Test+Plan`)
  #    sort     - The sort type. Options are: `modified`, `title`. Default: `modified` (e.g. `?sort=modified`)
  #    sort_dir - The sort direction. Options are: `asc` or `desc`. Default: `desc` (e.g. `?sort_dir=desc`)
  #    page     - The page within the resultset. Default: `1` (e.g. `?page=3`)
  #    per_page - The number of items per page. Default: `25`, Max: `100` (e.g. `?per_page=50`)
  #
  # The caller can also specify pagination params for :page and :per_page
  class GetDmps
    SOURCE = 'GET /dmps'

    SORT_OPTIONS = %w[title modified]
    SORT_DIRECTIONS = %w[asc desc]
    MAX_PAGE_SIZE = 100
    DEFAULT_PAGE_SIZE = 25
    DEFAULT_SORT_OPTION = 'modified'
    DEFAULT_SORT_DIR = 'desc'

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

      # Security check. If the Provenance is not allowed to see ALL orgs and the
      #                 requested org is not in the list of their allowed orgs, then
      #                 remove the requested org from the params
      unless provenance.fetch('org_access_level', '').downcase != 'all'
        rors = provenance.fetch('ror_list', []).map { |id| id.gsub('https://ror.org/', '') }
        # Reply with a 403 if the requested Org is not in the list of approved RORs
        if !params['org'].nil? && !rors.include?(params['org'])
          errors = "Invalid ROR. You may make requests for the following ROR ids: #{provenance.fetch('ror_list', [])}"
          return _respond(status: 403, errors:, event:) if provenance.nil?

        elsif params['org'].nil?
          # If they did not specify an Org, allow all of the valid ones
          params['org'] = rors.join('|')
        end
      end

      # We do not allow completely open ended queries at this point
      if params['org'].blank? && params['funder'].blank? && params['owner'].blank?
        return _respond(status: 400, errors: 'You must specify one of the following: org, funder, owner', event:)
      end

      resp = Uc3DmpId::Finder.search_dmps(args: params, logger:)
      dmps = resp.is_a?(Array) ? resp : []
      logger&.debug(message: 'Search returned the following index records:', details: dmps)

      # Perfom search operations
      term = params.fetch('search', '').to_s.strip.downcase
      unless term.blank?
        logger&.debug(message: "Searching results for #{term}")
        dmps = dmps.select do |dmp|
          dmp['title'].to_s.downcase.include?(term) || dmp['abstract'].to_s.downcase.include?(term)
        end
      end

      # Handle sort
      col = params['sort'].to_s.downcase
      dir = params['sort_dir'].to_s.downcase
      sort = SORT_OPTIONS.include?(col) ? col : DEFAULT_SORT_OPTION
      sort_dir = SORT_DIRECTIONS.include?(dir) ? dir : DEFAULT_SORT_DIR
      logger&.debug(message: "Sorting results: #{col}, #{dir}")
      dmps = dmps.sort do |a, b|
        sort_dir == 'desc' ? b[sort] <=> a[sort] : a[sort] <=> b[sort]
      end

      # Handle pagination
      dmps = _paginate_results(results: dmps, params:)
      logger&.debug(
        message: 'Paginated results:',
        details: {
          page: params['page'],
          per_page: params['per_page'],
          total_items: params['total_items'],
          total_pages: params['total_pages']
        }
      )

      # Fetch full DMP records for the results
      client = Uc3DmpDynamo::Client.new(table: ENV['DYNAMO_TABLE'])
      logger&.debug(message: 'Fetching DMP ID JSON for the results:')
      dmps = dmps.map { |dmp| Uc3DmpId::Finder.by_pk(p_key: dmp['pk'], client:, logger:, cleanse: true) }
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID) if dmps.nil?
      return _respond(status: 404, errors: Uc3DmpId::Helper::MSG_DMP_NOT_FOUND) if dmps.empty?

      logger&.debug(message: 'Found the following results:', details: dmps)
      _respond(status: 200, items: dmps, event:, params:)
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
      # rubocop:disable Metrics/AbcSize
      def _process_params(event:)
        params = event.fetch('queryStringParameters', {})
        params = {} if params.nil?

        # Convert the URI encoded '@' character if the `owner` param was provided
        params['owner'] = params['owner'].to_s.gsub('%40', '@') unless params['owner'].nil?

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

      # Paginate the results based on
      def _paginate_results(results: [], params:)
        params['total_items'] = results.length
        params['total_pages'] = (params['total_items'].to_f / params['per_page']).ceil

        # Ensure the current page is within valid bounds
        params['page'] = params['total_pages'] if params['page'] > params['total_pages']
        params['page'] = 1 if params['page'] < 1

        # Calculate the range of results for the current page
        start_index = (params['page'] - 1) * params['per_page']
        end_index = [start_index + params['per_page'] - 1, params['total_items'] - 1].min

        # Extract the results for the current page
        results[start_index..end_index]
      end

      # get the request path and params from the event
      def _url_from_event(event:)
        return '' unless event.is_a?(Hash)

        url = event.fetch('path', '/')
        return url if event['queryStringParameters'].nil?

        "#{url}?#{event['queryStringParameters'].map { |k, v| "#{k}=#{v}" }.join('&')}"
      end

      # Generate a pagination link
      def _build_link(url:, target_page:, per_page: DEFAULT_PAGE_SIZE)
        return nil if url.nil? || target_page.nil?

        link = _url_without_pagination(url:)
        return nil if link.nil?

        link += '?' unless link.include?('?')
        link += '&' unless link.end_with?('&') || link.end_with?('?')
        "#{link}page=#{target_page}&per_page=#{per_page}"
      end

      # Remove the pagination query parameters from the URL
      def _url_without_pagination(url:)
        return nil if url.nil? || !url.is_a?(String)

        parts = url.split('?')
        out = parts.first
        query_args = parts.length <= 1 ? [] : parts.last.split('&')
        query_args = query_args.reject do |arg|
          arg.start_with?('page=') || arg.start_with?('per_page=') ||
            arg.start_with?('total_items=') || arg.start_with?('total_pages=')
        end
        return out unless query_args.any?

        "#{out}?#{query_args.join('&')}"
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        url = _url_from_event(event:)
        body = {
          status: status.to_i,
          requested: _url_without_pagination(url: url),
          requested_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%L%Z'),
          total_items: items.is_a?(Array) ? items.length : 0,
          items: items,
          errors:,
          page: params['page'] || 1,
          per_page: params['per_page'] || DEFAULT_PAGE_SIZE,
          total_items: params['total_items'] || 0,
          total_pages: params['total_pages'] || 1
        }

        prv = body[:page] - 1
        nxt = body[:page] + 1
        last = body[:total_pages]

        body[:first] = _build_link(url:, target_page: 1, per_page: body[:per_page]) if body[:page] > 1
        body[:prev] = _build_link(url:, target_page: prv, per_page: body[:per_page]) if body[:page] > 1
        body[:next] = _build_link(url:, target_page: nxt, per_page: body[:per_page]) if body[:page] < last
        body[:last] = _build_link(url:, target_page: last, per_page: body[:per_page]) if body[:page] < last
        body.compact

        { statusCode: status.to_i, body: body.to_json, headers: {} }
      end
    end
  end
end
