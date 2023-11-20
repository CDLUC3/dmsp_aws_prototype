# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Paginator' do
  let!(:described_class) { Uc3DmpApiCore::Paginator }

  let!(:url) { 'https://api.example.com/dmps/' }

  describe 'paginate(params:, results:)' do
    let!(:results) { %w[a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7] }

    it 'returns the :results as-is if it is not an array' do
      expect(described_class.paginate(params: {}, results: 'foo')).to eql('foo')
    end

    it 'returns the :results as-is if :params is not a Hash' do
      expect(described_class.paginate(params: 'bar', results: ['foo'])).to eql(['foo'])
    end

    it 'returns the results as-is if the :results are empty' do
      expect(described_class.paginate(params: {}, results: [])).to eql([])
    end

    it 'returns the correct results for the first page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 1, per_page: 5, total_pages: 7 })
      expected = %w[a b c d e]
      expect(described_class.paginate(params: { page: 1, per_page: 5 }, results:)).to eql(expected)
    end

    it 'returns the correct :results for a middle page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 3, per_page: 5, total_pages: 7 })
      expected = %w[k l m n o]
      expect(described_class.paginate(params: { page: 3, per_page: 5 }, results:)).to eql(expected)
    end

    it 'returns the correct :results for the last page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 7, per_page: 5, total_pages: 7 })
      expected = %w[4 5 6 7]
      expect(described_class.paginate(params: { page: 7, per_page: 5 }, results:)).to eql(expected)
    end
  end

  describe 'pagination_meta(url:, item_count: 0, params: {})' do
    it 'returns the expected response meta information when there is only one page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 1, per_page: 5, total_pages: 1 })
      expected = {
        page: 1,
        per_page: 5,
        total_items: 4
      }
      result = described_class.pagination_meta(url:, item_count: 4, params: {})
      expect(compare_hashes(hash_a: result, hash_b: expected)).to be(true)
    end

    it 'returns the expected response meta information when on the first page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 1, per_page: 5, total_pages: 7 })
      expected = {
        page: 1,
        per_page: 5,
        total_items: 34,
        next: "#{url}?page=2&per_page=5",
        last: "#{url}?page=7&per_page=5"
      }
      result = described_class.pagination_meta(url:, item_count: 34, params: {})
      expect(compare_hashes(hash_a: result, hash_b: expected)).to be(true)
    end

    it 'returns the expected response meta information when on the last page' do
      allow(described_class).to receive(:_current_page).and_return({ page: 7, per_page: 5, total_pages: 7 })
      expected = {
        page: 7,
        per_page: 5,
        total_items: 34,
        first: "#{url}?page=1&per_page=5",
        prev: "#{url}?page=6&per_page=5"
      }
      result = described_class.pagination_meta(url:, item_count: 34, params: {})
      expect(compare_hashes(hash_a: result, hash_b: expected)).to be(true)
    end

    it 'returns the expected response meta information when all pagination links are necessary' do
      allow(described_class).to receive(:_current_page).and_return({ page: 3, per_page: 5, total_pages: 7 })
      expected = {
        page: 3,
        per_page: 5,
        total_items: 34,
        first: "#{url}?page=1&per_page=5",
        prev: "#{url}?page=2&per_page=5",
        next: "#{url}?page=4&per_page=5",
        last: "#{url}?page=7&per_page=5"
      }
      result = described_class.pagination_meta(url:, item_count: 34, params: {})
      expect(compare_hashes(hash_a: result, hash_b: expected)).to be(true)
    end

    it 'skips adding pagination urls if :url is nil' do
      allow(described_class).to receive(:_current_page).and_return({ page: 3, per_page: 5, total_pages: 7 })
      expected = {
        page: 3,
        per_page: 5,
        total_items: 34
      }
      result = described_class.pagination_meta(url: nil, item_count: 34, params: {})
      expect(compare_hashes(hash_a: result, hash_b: expected)).to be(true)
    end
  end

  describe '_current_page(item_count:, params:)' do
    it 'uses the DEFAULT_PAGE if no :page is in :params' do
      params = JSON.parse({ per_page: 5 }.to_json)
      expected = { page: 1, per_page: 5, total_pages: 4 }
      expect(described_class.send(:_current_page, item_count: 17, params:)).to eql(expected)
    end

    it 'uses the specified :page and :per_page' do
      params = JSON.parse({ page: 2, per_page: 5 }.to_json)
      expected = { page: 2, per_page: 5, total_pages: 4 }
      expect(described_class.send(:_current_page, item_count: 17, params:)).to eql(expected)
    end

    it 'does not allow pages below 1' do
      params = JSON.parse({ page: 0 }.to_json)
      expected = { page: 1, per_page: 25, total_pages: 1 }
      expect(described_class.send(:_current_page, item_count: 17, params:)).to eql(expected)
    end

    it 'does not allow pages beyond the total number of pages' do
      params = JSON.parse({ page: 2, per_page: 25 }.to_json)
      expected = { page: 1, per_page: 25, total_pages: 1 }
      expect(described_class.send(:_current_page, item_count: 17, params:)).to eql(expected)
    end

    it 'uses the DEFAULT_PER_PAGE if no :per_page is in :params' do
      params = JSON.parse({ page: 2 }.to_json)
      expected = { page: 2, per_page: 25, total_pages: 2 }
      expect(described_class.send(:_current_page, item_count: 34, params:)).to eql(expected)
    end

    it 'does not allow a :per_page specification to be above the MAXIMUM_PER_PAGE' do
      params = JSON.parse({ per_page: described_class::MAXIMUM_PER_PAGE + 1 }.to_json)
      expected = { page: 1, per_page: 25, total_pages: 1 }
      expect(described_class.send(:_current_page, item_count: 17, params:)).to eql(expected)
    end
  end

  describe '_build_link(url:, target_page:, per_page:)' do
    it 'returns nil if :url is nil' do
      result = described_class.send(:_build_link, url: nil, target_page: 1, per_page: 5)
      expect(result).to be_nil
    end

    it 'returns nil if :target_page is nil' do
      result = described_class.send(:_build_link, url:, target_page: nil, per_page: 5)
      expect(result).to be_nil
    end

    it 'uses the default :per_page if it is not specified' do
      result = described_class.send(:_build_link, url:, target_page: 1)
      dflt = described_class::DEFAULT_PER_PAGE
      expect(result).to eql("#{url}?page=1&per_page=#{dflt}")
    end

    it 'adds the correct :page and :per_page to the link' do
      result = described_class.send(:_build_link, url:, target_page: 44, per_page: 5)
      expect(result).to eql("#{url}?page=44&per_page=5")
    end

    it 'retains other query params' do
      url = "#{url}?foo=bar&page=1&bar=foo"
      result = described_class.send(:_build_link, url:, target_page: 2, per_page: 100)
      expect(result).to eql('?foo=bar&bar=foo&page=2&per_page=100')
    end
  end

  describe '_page_count(total:, per_page:)' do
    it 'returns 1 if :total is not present' do
      expect(described_class.send(:_page_count, total: nil, per_page: 1)).to be(1)
    end

    it 'returns 1 if :per_page is not present' do
      expect(described_class.send(:_page_count, total: 1, per_page: nil)).to be(1)
    end

    it 'returns 1 if :total is not a positive number' do
      expect(described_class.send(:_page_count, total: 0, per_page: 1)).to be(1)
    end

    it 'returns 1 if :per_page is not a positive number' do
      expect(described_class.send(:_page_count, total: 1, per_page: 0)).to be(1)
    end

    it 'returns the correct total number of pages' do
      expect(described_class.send(:_page_count, total: 2, per_page: 1)).to be(2)
      expect(described_class.send(:_page_count, total: 33, per_page: 25)).to be(2)
      expect(described_class.send(:_page_count, total: 100, per_page: 25.2)).to be(4)
    end
  end

  describe '_url_without_pagination(url:)' do
    it 'returns nil if :url is not present' do
      expect(described_class.send(:_url_without_pagination, url: nil)).to be_nil
    end

    it 'returns nil if :url is not a String' do
      expect(described_class.send(:_url_without_pagination, url: 13.3)).to be_nil
    end

    it 'strips off any pagination args from the query string' do
      url_in = "#{url}?page=3&per_page=25"
      expect(described_class.send(:_url_without_pagination, url: url_in)).to eql(url)
    end

    it 'returns other query string args' do
      url_in = "#{url}?bar=foo&page=3&per_page=25&foo=bar"
      expected = "#{url}?bar=foo&foo=bar"
      expect(described_class.send(:_url_without_pagination, url: url_in)).to eql(expected)
    end
  end
end
