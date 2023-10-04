# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Responder' do
  let!(:described_class) { Uc3DmpApiCore::Responder }

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
      resp = described_class.respond(status: 200, items:)
      expect(JSON.parse(resp[:body])['requested']).to eql('foo')
    end

    it 'uses the :page and :per_page if provided' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      result = described_class.respond(status: 200, items:, page: 2, per_page: 1)
      body = JSON.parse(result[:body])
      expect(body['page']).to be(2)
      expect(body['per_page']).to be(1)
    end

    it 'calls log_error if the status is 500' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      described_class.respond(status: 500, items:)
      expect(described_class).to have_received(:log_error).once
    end

    it 'does NOT call log_error if the status is NOT 500' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(described_class).to receive(:_paginate).and_return({})
      described_class.respond(status: 200, items:)
      expect(described_class).not_to have_received(:log_error)
    end

    it 'calls Paginator.paginate' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(Uc3DmpApiCore::Paginator).to receive(:paginate).and_return([])
      described_class.respond(status: 200, items:)
      expect(Uc3DmpApiCore::Paginator).to have_received(:paginate).once
    end

    it 'calls Paginator.pagination_meta' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      allow(Uc3DmpApiCore::Paginator).to receive(:pagination_meta).and_return({})
      described_class.respond(status: 200, items:)
      expect(Uc3DmpApiCore::Paginator).to have_received(:pagination_meta).once
    end

    it 'uses the default status' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      resp = described_class.respond(items:)
      expect(resp[:statusCode]).to eql(described_class::DEFAULT_STATUS_CODE)
    end

    # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
    it 'returns the expected Hash when there are no :errors' do
      allow(described_class).to receive(:_url_from_event).and_return(url)
      resp = described_class.respond(status: 402, items:)
      expect(resp[:statusCode]).to be(402)
      body = JSON.parse(resp[:body])
      expect(body['status']).to be(402)
      expect(body['requested']).to eql(url)
      expect(body['requested_at'].nil?).to be(false)
      expect(body['total_items']).to be(3)
      expect(body['items']).to eql(JSON.parse(items.to_json))
      expect(body['errors']).to eql([])
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
      resp = described_class.respond(status: 500, errors:, page: 2, per_page: 1)
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
      resp = described_class.respond(status: 301, items:, errors:, page: 2, per_page: 1)
      expect(resp[:statusCode]).to be(301)
      body = JSON.parse(resp[:body])
      expect(body['status']).to be(301)
      expect(body['requested']).to eql(url)
      expect(body['requested_at'].nil?).to be(false)
      expect(body['total_items']).to be(3)
      expect(body['items']).to eql([JSON.parse(items.to_json)[1]])
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

  describe '_url_from_event(event:)' do
    before do
      allow(described_class).to receive(:log_error).and_return(true)
    end

    it 'returns an empty String is :event is not a Hash' do
      expect(described_class.send(:_url_from_event, event: ['foo'])).to eql('')
      expect(described_class.send(:_url_from_event, event: 'foo')).to eql('')
    end

    it 'works if there are no :queryStringParameters' do
      event = JSON.parse({ path: 'api/foos' }.to_json)
      expect(described_class.send(:_url_from_event, event:)).to eql('api/foos')
    end

    it 'includes any :event :queryParameters' do
      event = JSON.parse({ path: 'api/foos', queryStringParameters: { foo: 'bar' } }.to_json)
      expect(described_class.send(:_url_from_event, event:)).to eql('api/foos?foo=bar')

      event = JSON.parse({ path: 'api/foos', queryStringParameters: { foo: 'bar', page: '2' } }.to_json)
      expect(described_class.send(:_url_from_event, event:)).to eql('api/foos?foo=bar&page=2')
    end
  end
end
