# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpExternalApi::Client' do
  let!(:described_class) { Uc3DmpExternalApi::Client }
  let!(:external_api_err) { Uc3DmpExternalApi::ExternalApiError }

  before do
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'call(url:, method:, body:, additional_headers:, debug:)' do
    let!(:url) { 'http://foo.bar' }

    it 'does not send the :body on an HTTP GET even if one was provided' do
      mock_httparty
      allow(described_class).to receive(:_options).and_return({})
      described_class.call(url:, body: 'foo')
      expect(described_class).to have_received(:_options).with(body: nil, additional_headers: {}, debug: false)
    end

    it 'raises an error if HTTParty does not receive a 2xx or 404 response code' do
      mock_httparty(code: 532, body: 'foo')
      allow(described_class).to receive(:_options).and_return({})
      msg = "#{format(MSG_ERROR_FROM_EXTERNAL_API, url:)} - status: 532, body: foo"
      expect { described_class.call(url:) }.to raise_error(external_api_err, msg)
    end

    it 'returns nil if HTTParty did not receive a response body but the response code was valid' do
      mock_httparty(code: 404, body: '')
      allow(described_class).to receive(:_options).and_return({})
      expect(described_class.call(url:, body: 'foo')).to be_nil
    end

    it 'returns the response body' do
      mock_httparty(code: 200, body: 'foo')
      allow(described_class).to receive(:_options).and_return({})
      allow(described_class).to receive(:_process_response).and_return('foo')
      expect(described_class.call(url:, body: 'foo')).to eql('foo')
    end

    it 'raises an error if there was a JSON parse error' do
      allow(described_class).to receive(:_process_response).and_raise(JSON::ParserError)
      msg = format(described_class::MSG_UNABLE_TO_PARSE, url:)
      expect { described_class.call(url:) }.to raise_error(external_api_err, msg)
    end

    it 'raises an error if there was a HTTParty error' do
      allow(HTTParty).to receive(:get).and_raise(HTTParty::Error)
      msg = format(described_class::MSG_HTTPARTY_ERR, url:)
      expect { described_class.call(url:) }.to raise_error(external_api_err, msg)
    end

    it 'raises an error if there was a URI parse error' do
      allow(URI).to receive(:initialize).and_raise(URI::InvalidURIError)
      msg = format(described_class::MSG_INVALID_URI, url:)
      expect { described_class.call(url:) }.to raise_error(external_api_err, msg)
    end
  end

  describe '_process_response(resp:)' do
    it 'returns nil if :resp is nil' do
      expect(described_class.send(:_process_response, resp: nil)).to be_nil
    end

    it 'returns nil if resp:body is nil' do
      expect(described_class.send(:_process_response, resp: { foo: 'bar' })).to be_nil
    end

    it 'returns a Hash if resp:body is a String and Content-Type header is application/json' do
      resp = HttpartyResponse.new
      resp.headers = { 'content-type': 'application/json' }
      resp.body = '[{"foo":"bar","baz":"123"}]'
      expect(described_class.send(:_process_response, resp:)).to eql(JSON.parse(resp.body))
    end

    it 'returns a String if Content-Type header is NOT application/json' do
      resp = HttpartyResponse.new
      resp.headers = { 'content-type': 'application/foo' }
      resp.body = 'foo bar baz'
      expect(described_class.send(:_process_response, resp:)).to eql(resp.body)
    end
  end

  describe '_headers(additional_headers:)' do
    # rubocop:disable RSpec/ExampleLength
    it 'uses the default env, domain and admin email if the ENV variables are not set' do
      ENV.delete('LAMBDA_ENV')
      ENV.delete('DOMAIN')
      ENV.delete('ADMIN_EMAIL')
      expected = {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': 'DMPTool  - dmptool.org (mailto: dmptool@ucop.edu)'
      }
      expect(described_class.send(:_headers)).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'uses the domain and admin email specified in the ENV variables' do
      ENV['LAMBDA_ENV'] = 'foo'
      ENV['DOMAIN'] = 'foo.bar'
      ENV['ADMIN_EMAIL'] = 'foo@bar.edu'
      expected = {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': 'DMPTool foo - foo.bar (mailto: foo@bar.edu)'
      }
      expect(described_class.send(:_headers)).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'merges the :additional_headers' do
      hdrs = { Foo: 'Bar', Accept: 'foo' }
      result = described_class.send(:_headers, additional_headers: hdrs)
      hdrs.each_key do |key|
        expect(result[:headers][key]).to eql(hdrs[key])
      end
    end
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  describe '_options(body:, additional_headers:, debug:)' do
    it 'can handle no :additional_headers' do
      allow(described_class).to receive(:_headers).and_return({ Foo: 'Bar' })
      body = { foo: 'bar' }
      result = described_class.send(:_options, body:, debug: true)
      expect(result[:body]).to eql(JSON.parse(body.to_json))
      expect(result[:follow_redirects]).to be(true)
      expect(result[:limit]).to be(6)
      expect(result[:debug_output]).to eql($stdout)
      expect(result[:headers]).to eql({ Foo: 'Bar' })
    end

    it 'defaults to :debug false' do
      allow(described_class).to receive(:_headers).and_return({ Foo: 'Bar' })
      body = { foo: 'bar' }
      result = described_class.send(:_options, body:, additional_headers: hdrs)
      expect(result[:body]).to eql(JSON.parse(body.to_json))
      expect(result[:follow_redirects]).to be(true)
      expect(result[:limit]).to be(6)
      expect(result[:debug_output]).to be_nil
      hdrs.each_key do |key|
        expect(result[:headers][key]).to eql(hdrs[key])
      end
    end

    it 'can handle a missing :body' do
      hdrs = { Foo: 'Bar', 'User-Agent': 'foo' }
      allow(described_class).to receive(:_headers).and_return(hdrs)
      result = described_class.send(:_options, additional_headers: hdrs, debug: true)
      expect(result[:body]).to be_nil
      expect(result[:follow_redirects]).to be(true)
      expect(result[:limit]).to be(6)
      expect(result[:debug_output]).to eql($stdout)
      expect(result[:headers]).to eql(hdrs)
    end

    it 'returns the expected result' do
      body = { foo: 'bar' }
      hdrs = { Foo: 'Bar', 'User-Agent': 'foo' }
      allow(described_class).to receive(:_headers).and_return(hdrs)
      result = described_class.send(:_options, body:, additional_headers: hdrs, debug: true)
      expect(result[:body]).to eql(JSON.parse(body.to_json))
      expect(result[:follow_redirects]).to be(true)
      expect(result[:limit]).to be(6)
      expect(result[:debug_output]).to eql($stdout)
      expect(result[:headers]).to eql(hdrs)
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
