# frozen_string_literal: true

module Uc3DmpApiCore
  # Use Rails' ActiveResource to communicate with the DMPHub REST API
  class Paginator
    DEFAULT_PAGE = 1
    DEFAULT_PER_PAGE = 25
    MAXIMUM_PER_PAGE = 250

    class << self
      # rubocop:disable Metrics/AbcSize
      def paginate(results:, params: {})
        return results unless results.is_a?(Array) && results.any? && params.is_a?(Hash)

        current = _current_page(item_count: results.length, params:)
        # Just return as is if there is only one page
        return results if current[:total_pages] == 1 || current[:per_page] >= results.length

        # Calculate the offset and extract those results
        offset = current[:page] == 1 ? 0 : (current[:page] - 1) * current[:per_page]
        results[offset, current[:per_page]]
      end
      # rubocop:enable Metrics/AbcSize

      # Construct the pagination meta information that will be included in the response
      # rubocop:disable Metrics/AbcSize
      def pagination_meta(url:, item_count: 0, params: {})
        prms = _current_page(item_count:, params:)

        hash = { page: prms[:page], per_page: prms[:per_page], total_items: item_count }
        return hash if prms[:total_pages] == 1 || item_count <= prms[:per_page]

        prv = prms[:page] - 1
        nxt = prms[:page] + 1
        last = prms[:total_pages]

        hash[:first] = _build_link(url:, target_page: 1, per_page: prms[:per_page]) if prms[:page] > 1
        hash[:prev] = _build_link(url:, target_page: prv, per_page: prms[:per_page]) if prms[:page] > 1
        hash[:next] = _build_link(url:, target_page: nxt, per_page: prms[:per_page]) if prms[:page] < last
        hash[:last] = _build_link(url:, target_page: last, per_page: prms[:per_page]) if prms[:page] < last
        hash.compact
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Fetch the current :page and :per_page from the params or use the defaults
      # rubocop:disable Metrics/AbcSize
      def _current_page(item_count: 0, params: {})
        page = params.fetch('page', DEFAULT_PAGE).to_i
        page = DEFAULT_PAGE if page.nil? || page.to_i <= 1
        per_page = params.fetch('per_page', DEFAULT_PER_PAGE).to_i
        per_page = DEFAULT_PER_PAGE if per_page.nil? || per_page.to_i >= MAXIMUM_PER_PAGE || per_page.to_i < 1

        total_pages = _page_count(total: item_count, per_page:)
        page = total_pages if page > total_pages

        { page: page.to_i, per_page: per_page.to_i, total_pages: total_pages.to_i }
      end
      # rubocop:enable Metrics/AbcSize

      # Generate a pagination link
      # --------------------------------------------------------------------------------
      def _build_link(url:, target_page:, per_page: DEFAULT_PER_PAGE)
        return nil if url.nil? || target_page.nil?

        link = _url_without_pagination(url:)
        return nil if link.nil?

        link += '?' unless link.include?('?')
        link += '&' unless link.end_with?('&') || link.end_with?('?')
        "#{link}page=#{target_page}&per_page=#{per_page}"
      end

      # Determine the total number of pages
      # --------------------------------------------------------------------------------
      def _page_count(total:, per_page: DEFAULT_PER_PAGE)
        return 1 if total.nil? || per_page.nil? || !total.positive? || !per_page.positive?

        (total.to_f / per_page).ceil
      end

      # Remove the pagination query parameters from the URL
      # --------------------------------------------------------------------------------
      def _url_without_pagination(url:)
        return nil if url.nil? || !url.is_a?(String)

        parts = url.split('?')
        out = parts.first
        query_args = parts.length <= 1 ? [] : parts.last.split('&')
        query_args = query_args.reject { |arg| arg.start_with?('page=') || arg.start_with?('per_page=') }
        return out unless query_args.any?

        "#{out}?#{query_args.join('&')}"
      end
    end
  end
end
