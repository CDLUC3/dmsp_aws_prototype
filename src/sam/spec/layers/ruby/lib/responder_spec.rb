# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Responder' do
  let!(:described_class) { Responder }

  let!(:url) { 'https://api.example.com/dmps/' }

  describe 'respond(status:, items:, errors:, **args)' do
    let!(:items) { [{ foo: 'bar' }, { bar: 'foo' }, { baz: 'foo-bar' }] }
    let!(:errors) { ['Foo!', 'Bar!'] }

    before do
      mock_ssm(value: 'foo')
      allow(described_class).to receive(:log_error).and_return(true)
    end

    it 'calls ssm_reader.get_ssm_value to get the base api URL' do
      allow(described_class).to receive(:get_ssm_value).and_return(url)
      allow(described_class).to receive(:_url_from_event).and_return(nil)
      resp = described_class.respond(status: 200, items: items)
      expect(JSON.parse(resp[:body])['requested']).to eql('foo')
    end

    it 'calls _cleanse_dmp_json for each :item' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_cleanse_dmp_json).and_return(true)
      described_class.respond(status: 200, items: items)
      expect(described_class).to have_received(:_cleanse_dmp_json).thrice
    end

    it 'uses the :page and :per_page if provided' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      result = described_class.respond(status: 200, items: items, page: 2, per_page: 1)
      body = JSON.parse(result[:body])
      expect(body['page']).to be(2)
      expect(body['per_page']).to be(1)
    end

    it 'calls log_error if the status is 500' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_cleanse_dmp_json).and_return({})
      described_class.respond(status: 500, items: items)
      expect(described_class).to have_received(:log_error).once
    end

    it 'does NOT call log_error if the status is NOT 500' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_cleanse_dmp_json).and_return({})
      allow(described_class).to receive(:_paginate).and_return({})
      described_class.respond(status: 200, items: items)
      expect(described_class).not_to have_received(:log_error)
    end

    it 'calls _paginate' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_cleanse_dmp_json).and_return({})
      allow(described_class).to receive(:_paginate).and_return(true)
      described_class.respond(status: 200, items: items)
      expect(described_class).to have_received(:_paginate).once
    end

    it 'uses the default status' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_cleanse_dmp_json).and_return({})
      resp = described_class.respond(items: items)
      expect(resp[:statusCode]).to eql(described_class::DEFAULT_STATUS_CODE)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'returns the expected Hash when there are no :errors' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      resp = described_class.respond(status: 402, items: items)
      expect(resp[:statusCode]).to be(402)
      body = JSON.parse(resp[:body])
      expect(body['status']).to be(402)
      expect(body['requested']).to eql(url)
      expect(body['requested_at'].nil?).to be(false)
      expect(body['total_items']).to be(3)
      expect(body['items']).to eql(JSON.parse(items.to_json))
      expect(body['errors']).to be_nil
      expect(body['page']).to eql(described_class::DEFAULT_PAGE)
      expect(body['per_page']).to eql(described_class::DEFAULT_PER_PAGE)
      expect(body['first']).to be_nil
      expect(body['prev']).to be_nil
      expect(body['next']).to be_nil
      expect(body['last']).to be_nil
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'returns the expected Hash when there are no :items' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:log_error).and_return(true)
      resp = described_class.respond(status: 500, errors: errors, page: 2, per_page: 1)
      expect(resp[:statusCode]).to be(500)
      body = JSON.parse(resp[:body])
      expect(body['status']).to be(500)
      expect(body['requested']).to eql(url)
      expect(body['requested_at'].nil?).to be(false)
      expect(body['total_items']).to be(0)
      expect(body['items']).to eql([])
      expect(body['errors']).to eql(JSON.parse(errors.to_json))
      expect(body['page']).to be(1) # Even though we said 2, there is only one possible page
      expect(body['per_page']).to be(1)
      expect(body['prev']).to be_nil
      expect(body['first']).to be_nil
      expect(body['next']).to be_nil
      expect(body['last']).to be_nil
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'returns the expected Hash when both :items and :errors are provided' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      resp = described_class.respond(status: 301, items: items, errors: errors, page: 2, per_page: 1)
      expect(resp[:statusCode]).to be(301)
      body = JSON.parse(resp[:body])
      expect(body['status']).to be(301)
      expect(body['requested']).to eql(url)
      expect(body['requested_at'].nil?).to be(false)
      expect(body['total_items']).to be(3)
      expect(body['items']).to eql(JSON.parse(items.to_json))
      expect(body['errors']).to eql(JSON.parse(errors.to_json))
      expect(body['page']).to be(2)
      expect(body['per_page']).to be(1)
      expect(body['first']).to eql("#{url}?page=1&per_page=1")
      expect(body['prev']).to eql("#{url}?page=1&per_page=1")
      expect(body['next']).to eql("#{url}?page=3&per_page=1")
      expect(body['last']).to eql("#{url}?page=3&per_page=1")
    end
    # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength
  end

  describe 'log_error(source:, message:, details: {}, event: {})' do
    # Note that tests that verify that the errors actually end up in CloudWatch occur in the
    # API tests which have access to the AWS resources
    it 'returns false is :source is nil' do
      expect(described_class.log_error(source: nil, message: 'Lorem ipsum')).to be(false)
    end

    it 'returns false is :message is nil' do
      expect(described_class.log_error(source: 'api/foos', message: nil)).to be(false)
    end

    it 'returns false if _notify_administrator fails' do
      allow(described_class).to receive(:_notify_administrator).and_return(nil)
      expect(described_class.log_error(source: 'api/foo', message: 'Lorem ipsum')).to be(false)
    end

    it 'returns true if _notify_administrator succeeds' do
      allow(described_class).to receive(:_notify_administrator).and_return('foo')
      expect(described_class.log_error(source: 'api/foo', message: 'Lorem ipsum')).to be(true)
    end
  end

  describe '_url_from_event(event:)' do
    before do
      allow(described_class).to receive(:log_error).and_return(true)
    end

    it 'returns an empty String is :event is not a Hash' do
      expect(described_class._url_from_event(event: ['foo'])).to eql('')
      expect(described_class._url_from_event(event: 'foo')).to eql('')
    end

    it 'works if there are no :queryStringParameters' do
      event = JSON.parse({ path: 'api/foos' }.to_json)
      expect(described_class._url_from_event(event: event)).to eql('api/foos')
    end

    it 'includes any :event :queryParameters' do
      event = JSON.parse({ path: 'api/foos', queryStringParameters: { foo: 'bar' } }.to_json)
      expect(described_class._url_from_event(event: event)).to eql('api/foos?foo=bar')

      event = JSON.parse({ path: 'api/foos', queryStringParameters: { foo: 'bar', page: '2' } }.to_json)
      expect(described_class._url_from_event(event: event)).to eql('api/foos?foo=bar&page=2')
    end
  end

  describe '_notify_administrator(source:, details:, event:)' do
    # Note that tests that verify that the message gets posted to SNS occur in the API tests
    # which have access to the AWS resources
    let!(:source) { 'Example class.method' }
    let!(:details) { { detail1: 'foo-detail1', detail2: 'foo-detail2' } }
    let!(:event) { { event1: 'foo-event1', event2: 'foo-event2' } }

    before do
      mock_ssm(value: 'foo')
      mock_sns
      allow(described_class).to receive(:log_error).and_return(true)
    end

    it 'includes the expected info in the email message' do
      sns_client = SnsClient.new(true)
      allow(sns_client).to receive(:publish).and_return('Message sent:')
      message = described_class._notify_administrator(source: source, details: details, event: event)
      expect(message.start_with?('Message sent')).to be(true)
    end

    it 'handles AWS errors with posting the message to SNS' do
      SnsClient.new(false)
      allow(described_class).to receive(:_notify_administrator).and_return(nil)
      described_class._notify_administrator(source: source, details: details)
      expect(described_class).to have_received(:_notify_administrator).once
    end
  end

  describe '_paginate(url:, item_count:, body:, page:, per_page:)' do
    it 'does not add pagination if the :url is nil' do
      result = described_class._paginate(url: nil, item_count: 3, body: { foo: 'bar' }, page: 2, per_page: 1)
      expect(result).to eql({ foo: 'bar' })
    end

    it 'does not add pagination if the :total_nbr_items is nil' do
      result = described_class._paginate(url: url, item_count: nil, body: { foo: 'bar' }, page: 2, per_page: 1)
      expect(result).to eql({ foo: 'bar' })
    end

    it 'does not add pagination if the :body is not a Hash' do
      result = described_class._paginate(url: url, item_count: 3, body: 3.3, page: 2, per_page: 1)
      expect(result).to be(3.3)
    end

    it 'uses the default :page and :per_page if none are specified' do
      result = described_class._paginate(url: url, item_count: 3, body: {})
      expect(result[:page]).to eql(described_class::DEFAULT_PAGE)
      expect(result[:per_page]).to eql(described_class::DEFAULT_PER_PAGE)
    end

    it 'does not add a :first link if it is on page 1' do
      result = described_class._paginate(url: url, item_count: 3, body: {}, page: 1, per_page: 1)
      expect(result[:first]).to be_nil
    end

    it 'does not add a :first link if there is only one page' do
      result = described_class._paginate(url: url, item_count: 1, body: {}, page: 1, per_page: 1)
      expect(result[:first]).to be_nil
    end

    it 'does not add a pagination links if there is only one page' do
      result = described_class._paginate(url: url, item_count: 1, body: {}, page: 1, per_page: 1)
      expect(result[:first]).to be_nil
      expect(result[:prev]).to be_nil
      expect(result[:next]).to be_nil
      expect(result[:last]).to be_nil
    end

    it 'does not add a :prev link if it is on page 1' do
      result = described_class._paginate(url: url, item_count: 3, body: {}, page: 1, per_page: 1)
      expect(result[:prev]).to be_nil
    end

    it 'does not add a :next link if it is on the last page' do
      result = described_class._paginate(url: url, item_count: 3, body: {}, page: 3, per_page: 1)
      expect(result[:next]).to be_nil
    end

    it 'does not add a :last link if it is on the last page' do
      result = described_class._paginate(url: url, item_count: 3, body: {}, page: 3, per_page: 1)
      expect(result[:last]).to be_nil
    end

    # rubocop:disable RSpec/MultipleExpectations
    it 'adds the correct links' do
      result = described_class._paginate(url: url, item_count: 5, body: {}, page: 3, per_page: 1)
      expect(result[:page]).to be(3)
      expect(result[:per_page]).to be(1)
      expect(result[:first]).to eql("#{url}?page=1&per_page=1")
      expect(result[:prev]).to eql("#{url}?page=2&per_page=1")
      expect(result[:next]).to eql("#{url}?page=4&per_page=1")
      expect(result[:last]).to eql("#{url}?page=5&per_page=1")
    end
  end
  # rubocop:enable RSpec/MultipleExpectations

  describe '_pagination_link(url:, target_page:, per_page:)' do
    it 'returns nil if :url is nil' do
      result = described_class._pagination_link(url: nil, target_page: 1, per_page: 5)
      expect(result).to be_nil
    end

    it 'returns nil if :target_page is nil' do
      result = described_class._pagination_link(url: url, target_page: nil, per_page: 5)
      expect(result).to be_nil
    end

    it 'uses the default :per_page if it is not specified' do
      result = described_class._pagination_link(url: url, target_page: 1)
      dflt = described_class::DEFAULT_PER_PAGE
      expect(result).to eql("#{url}?page=1&per_page=#{dflt}")
    end

    it 'adds the correct :page and :per_page to the link' do
      result = described_class._pagination_link(url: url, target_page: 44, per_page: 5)
      expect(result).to eql("#{url}?page=44&per_page=5")
    end

    it 'retains other query params' do
      url = "#{url}?foo=bar&page=1&bar=foo"
      result = described_class._pagination_link(url: url, target_page: 2, per_page: 100)
      expect(result).to eql('?foo=bar&bar=foo&page=2&per_page=100')
    end
  end

  describe '_page_count(total:, per_page:)' do
    it 'returns 1 if :total is not present' do
      expect(described_class._page_count(total: nil, per_page: 1)).to be(1)
    end

    it 'returns 1 if :per_page is not present' do
      expect(described_class._page_count(total: 1, per_page: nil)).to be(1)
    end

    it 'returns 1 if :total is not a positive number' do
      expect(described_class._page_count(total: 0, per_page: 1)).to be(1)
    end

    it 'returns 1 if :per_page is not a positive number' do
      expect(described_class._page_count(total: 1, per_page: 0)).to be(1)
    end

    it 'returns the correct total number of pages' do
      expect(described_class._page_count(total: 2, per_page: 1)).to be(2)
      expect(described_class._page_count(total: 33, per_page: 25)).to be(2)
      expect(described_class._page_count(total: 100, per_page: 25.2)).to be(4)
    end
  end

  describe '_url_without_pagination(url:)' do
    it 'returns nil if :url is not present' do
      expect(described_class._url_without_pagination(url: nil)).to be_nil
    end

    it 'returns nil if :url is not a String' do
      expect(described_class._url_without_pagination(url: 13.3)).to be_nil
    end

    it 'strips off any pagination args from the query string' do
      url_in = "#{url}?page=3&per_page=25"
      expect(described_class._url_without_pagination(url: url_in)).to eql(url)
    end

    it 'returns other query string args' do
      url_in = "#{url}?bar=foo&page=3&per_page=25&foo=bar"
      expected = "#{url}?bar=foo&foo=bar"
      expect(described_class._url_without_pagination(url: url_in)).to eql(expected)
    end
  end

  describe '_cleanse_dmp_json(json:)' do
    it 'returns the :json as is if it is not a Hash or an Array' do
      json = 'foo'
      expect(described_class._cleanse_dmp_json(json: json)).to eql(json)
    end

    it 'calls itdescribed_class recursively for each item if it is an Array' do
      json = [
        { dmphub_a: 'foo' },
        { foo: 'bar' }
      ]
      expect(described_class._cleanse_dmp_json(json: json)).to eql([{ foo: 'bar' }])
    end

    it 'removes all entries that start with "dmphub"' do
      json = [
        { dmphub_a: 'foo' },
        { dmphubb: 'bar' }
      ]
      expect(described_class._cleanse_dmp_json(json: json)).to eql([])
    end

    it 'removes the PK and SK entries' do
      json = [
        { PK: 'DMP#foo' },
        { SK: 'VERSION#bar' }
      ]
      expect(described_class._cleanse_dmp_json(json: json)).to eql([])
    end

    # rubocop:disable RSpec/ExampleLength
    it 'recursively cleanses child Hashes and Arrays' do
      json = {
        'child-1': {
          dmphub_a: 'foo',
          foo: 'bar'
        },
        'child-2': [
          { dmphub_b: 'bar' },
          { bar: 'foo' }
        ],
        dmphub_c: {
          baz: 'hey'
        }
      }
      expected = { 'child-1': { foo: 'bar' }, 'child-2': [{ bar: 'foo' }] }
      result = described_class._cleanse_dmp_json(json: json)
      expect(result).to eql(expected)
    end
  end
  # rubocop:enable RSpec/ExampleLength

  # Helper function that compares 2 hashes regardless of the order of their keys
  def compare_hashes(hash_a: {}, hash_b: {})
    a_keys = hash_a.keys.sort { |a, b| a <=> b }
    b_keys = hash_b.keys.sort { |a, b| a <=> b }
    return false unless a_keys == b_keys

    valid = true
    a_keys.each { |key| valid = false unless hash_a[key] == hash_b[key] }
    valid
  end
end
