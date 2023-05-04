# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Functions::GetFunders' do
  let!(:described_class) { Functions::GetFunders }

  before do
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'process(event:, context:)' do
    it 'returns a 400 if the query string does not contain a :search' do
      event = aws_event
      err = Uc3DmpApiCore::MSG_INVALID_ARGS
      allow(described_class).to receive(:_respond).and_return('foo')
      described_class.process(event: event, context: aws_context)
      expect(described_class).to have_received(:_respond).with(status: 400, errors: [err], event: event).once
    end

    it 'returns a 400 if the query string contains a :search that is fewer than 3 characters' do
      event = aws_event(args: { queryStringParameters: { search: 'fo' } })
      err = Uc3DmpApiCore::MSG_INVALID_ARGS
      allow(described_class).to receive(:_respond).and_return('foo')
      described_class.process(event: event, context: aws_context)
      expect(described_class).to have_received(:_respond).with(status: 400, errors: [err], event: event).once
    end

    it 'returns a 500 if a connection to the database could not be established' do
      event = aws_event(args: { queryStringParameters: { search: 'foo' } })
      err = Uc3DmpApiCore::MSG_SERVER_ERROR
      allow(described_class).to receive(:_respond).and_return('foo')
      allow(described_class).to receive(:_establish_connection).and_return(false)
      described_class.process(event: event, context: aws_context)
      expect(described_class).to have_received(:_respond).with(status: 500, errors: [err], event: event).once
    end

    it 'returns a 200 and no :items if the search returned no results' do
      event = aws_event(args: { queryStringParameters: { search: 'foo' } })
      allow(described_class).to receive(:_respond).and_return('foo')
      allow(described_class).to receive(:_establish_connection).and_return(true)
      allow(described_class).to receive(:_search).and_return([])
      described_class.process(event: event, context: aws_context)
      expect(described_class).to have_received(:_respond).with(status: 200, items: [], event: event).once
    end

    it 'returns a 200 and funder items' do
      event = aws_event(args: { queryStringParameters: { search: 'foo' } })
      allow(described_class).to receive(:_respond).and_return('foo')
      allow(described_class).to receive(:_establish_connection).and_return(true)
      allow(described_class).to receive(:_search).and_return(['foo'])
      allow(described_class).to receive(:_results_to_response).and_return(['bar'])
      described_class.process(event: event, context: aws_context)
      expected = { status: 200, items: ['bar'], params: JSON.parse({ search: 'foo' }.to_json), event: event }
      expect(described_class).to have_received(:_respond).with(expected).once
    end
  end

  describe '_establish_connection' do
    it 'calls the Uc3DmpRds gem to connect to the database' do
      allow(Uc3DmpApiCore::SsmReader).to receive(:get_ssm_value).and_return('foo')
      allow(Uc3DmpApiCore::SsmReader).to receive(:get_ssm_value).and_return('bar')
      allow(Uc3DmpRds::Adapter).to receive(:connect)
      described_class.send(:_establish_connection)
      expect(Uc3DmpRds::Adapter).to have_received(:connect).once
    end
  end

  describe '_search' do
    it 'calls the Uc3DmpRds gem to execute the query' do
      allow(Uc3DmpRds::Adapter).to receive(:execute_query)
      described_class.send(:_search, term: 'foo')
      expect(Uc3DmpRds::Adapter).to have_received(:execute_query).once
    end
  end

  describe '_respond(status:, items:, errors:, event:, params:)' do
    it 'calls Uc3DmpApiCore gem to format the Lambda response' do
      allow(Uc3DmpApiCore::Responder).to receive(:respond)
      described_class.send(:_respond, status: 200, items: [])
      expect(Uc3DmpApiCore::Responder).to have_received(:respond).once
    end
  end

  describe '_results_to_response(term:, results:)' do
    let!(:results) do
      [
        { name: 'Example Institution (eu.gov)', fundref_id: 'abcdefg', org_id: 123 },
        { name: 'Example Org (example.com)', fundref_id: 'zyxw' },
        { name: 'Missing Fundref (missing.net)' },
        { name: 'API Funder (api.gov)', fundref_id: '12345', api_target: 'http:/foo.edu', api_guidance: 'foo',
          api_query_fields: '[{"label":"Foo","query_string_key":"foo}]' }
      ]
    end

    it 'returns an empty array if :term is not a String' do
      items = described_class.send(:_results_to_response, term: 123, results: JSON.parse(results.to_json))
      expect(items).to eql([])
    end

    it 'returns an empty array if :term is blank' do
      items = described_class.send(:_results_to_response, term: '   ', results: JSON.parse(results.to_json))
      expect(items).to eql([])
    end

    it 'returns an empty array if :results is not an Array' do
      expect(described_class.send(:_results_to_response, term: 'foo', results: 'bar')).to eql([])
    end

    it 'returns an empty array if :results is an empty array' do
      expect(described_class.send(:_results_to_response, term: 'foo', results: [])).to eql([])
    end

    it 'adds the Fundref prefix to the fundref_id if it is missing' do
      allow(described_class).to receive(:_weigh).and_return(1)
      recs = [results.first]
      expected = { identifier: "#{described_class::FUNDREF_URI_PREFIX}#{recs.first[:fundref_id]}", type: 'fundref' }
      items = described_class.send(:_results_to_response, term: 'instit', results: JSON.parse(recs.to_json))
      expect(items.first[:funder_id]).to eql(expected)
    end

    it 'weighs each result' do
      allow(described_class).to receive(:_weigh).and_return(1)
      items = [results.first, results.last]
      described_class.send(:_results_to_response, term: 'instit', results: JSON.parse(items.to_json))
      expect(described_class).to have_received(:_weigh).twice
    end

    it 'returns what we expect when the record has only a name' do
      allow(described_class).to receive(:_weigh).and_return(1)
      recs = [{ name: 'Missing Fundref (missing.net)' }]
      items = described_class.send(:_results_to_response, term: 'missing', results: JSON.parse(recs.to_json))
      expect(items.first[:name]).to eql(recs.first[:name])
      expect(items.first[:weight]).to be(1)
      expect(items.first[:funder_id]).to be(nil)
      expect(items.first[:funder_api]).to be(nil)
      expect(items.first[:funder_api_guidance]).to be(nil)
      expect(items.first[:funder_api_query_fields]).to be(nil)
    end

    it 'returns what we expect when the record has all data elements' do
      allow(described_class).to receive(:_weigh).and_return(1)
      recs = [results.last]
      items = described_class.send(:_results_to_response, term: 'example', results: JSON.parse(recs.to_json))
      expected = { identifier: "#{described_class::FUNDREF_URI_PREFIX}#{recs.first[:fundref_id]}", type: 'fundref' }
      expect(items.first[:name]).to eql(recs.first[:name])
      expect(items.first[:weight]).to be(1)
      expect(items.first[:funder_id]).to eql(expected)
      expect(items.first[:homepage]).to eql(recs.first[:homepage])
      expect(items.first[:dmproadmap_host_id]).to eql(recs.first[:uri])
      expect(items.first[:funder_api]).to eql(recs.first[:api_target])
      expect(items.first[:funder_api_guidance]).to eql(recs.first[:api_guidance])
      expect(items.first[:funder_api_query_fields]).to eql(recs.first[:api_query_fields])
    end

    it 'sorts the results based on weight and name' do
      recs = [results.first, results.last]
      allow(described_class).to receive(:_weigh).with(term: 'foo', org: JSON.parse(recs.first.to_json))
                                                .and_return(0)
      allow(described_class).to receive(:_weigh).with(term: 'foo', org: JSON.parse(recs.last.to_json))
                                                .and_return(5)
      items = described_class.send(:_results_to_response, term: 'foo', results: JSON.parse(recs.to_json))
      expect(items.first[:name]).to eql(recs.last[:name])
      expect(items.last[:name]).to eql(recs.first[:name])
    end
  end

  describe '_weigh(term:, org:)' do
    let!(:org) { { name: 'example university', acronyms: '[\'xyz\']', aliases: '[\'foo\', \'bar\']' } }

    it 'returns zero if :term is not a String' do
      expect(described_class.send(:_weigh, term: 123, org: org)).to be(0)
    end

    it 'returns zero if :org is not a Hash' do
      expect(described_class.send(:_weigh, term: '123', org: 123)).to be(0)
    end

    it 'returns zero if org:name is not a String' do
      expect(described_class.send(:_weigh, term: '123', org: { foo: 'foo' })).to be(0)
    end

    it 'applies the correct score when we have an acronym match' do
      expect(described_class.send(:_weigh, term: 'xyz', org: JSON.parse(org.to_json))).to be(1)
    end

    it 'applies the correct score when we have an alias match' do
      expect(described_class.send(:_weigh, term: 'foo', org: JSON.parse(org.to_json))).to be(1)
    end

    it 'applies the correct score when we have a partial name match' do
      expect(described_class.send(:_weigh, term: 'xample', org: JSON.parse(org.to_json))).to be(1)
    end

    it 'applies the correct score when we have a starts with name match' do
      expect(described_class.send(:_weigh, term: 'exam', org: JSON.parse(org.to_json))).to be(2)
    end

    it 'applies the correct score when we have an org_id' do
      org = { name: 'foo', org_id: 123 }
      expect(described_class.send(:_weigh, term: 'exam', org: JSON.parse(org.to_json))).to be(1)
    end

    it 'is possible to have a score of zero' do
      org = { name: 'baz' }
      expect(described_class.send(:_weigh, term: 'exam', org: JSON.parse(org.to_json))).to be(0)
    end

    it 'is possible to get a score of 3' do
      org[:acronyms] = '[\'exam\']'
      org[:org_id] = 123
      expect(described_class.send(:_weigh, term: 'xam', org: JSON.parse(org.to_json))).to be(3)
    end

    it 'is possible to get a score of 5 (highest score)' do
      org[:acronyms] = '[\'exam\']'
      org[:aliases] = '[\'baz\', \'exam\']'
      org[:org_id] = 123
      expect(described_class.send(:_weigh, term: 'exam', org: JSON.parse(org.to_json))).to be(5)
    end
  end
end
