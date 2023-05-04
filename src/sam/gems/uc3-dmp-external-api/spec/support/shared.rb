# frozen_string_literal: true

require 'ostruct'

# Mock HTTParty
HttpartyResponse = Struct.new('HTTPartyResponse', :code, :body)

# rubocop:disable Metrics/AbcSize
def mock_httparty(code: 200, body: '', headers: {})
  resp = HttpartyResponse.new
  allow(resp).to receive(:code).and_return(code)
  allow(resp).to receive(:body).and_return(body.to_s)
  allow(resp).to receive(:headers).and_return(headers)
  allow(HTTParty).to receive(:delete).and_return(resp)
  allow(HTTParty).to receive(:get).and_return(resp)
  allow(HTTParty).to receive(:post).and_return(resp)
  allow(HTTParty).to receive(:put).and_return(resp)
  allow(HTTParty).to receive(:patch).and_return(resp)
  resp
end
# rubocop:enable Metrics/AbcSize
