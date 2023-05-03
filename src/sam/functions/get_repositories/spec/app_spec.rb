# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Functions::GetRepositories' do
  let!(:described_class) { Functions::GetRepositories }

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
        { name: 'Example Repo (er.com)', description: 'foo', uri: 'https://bar.foo', homepage: 'http://er.com' },
        { name: 'Example Repo Bland (example.com)' }
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

    it 'weighs each result' do
      allow(described_class).to receive(:_weigh).and_return(1)
      items = [results.first, results.last]
      described_class.send(:_results_to_response, term: 'example', results: JSON.parse(items.to_json))
      expect(described_class).to have_received(:_weigh).twice
    end

    it 'returns what we expect when the record has only a name' do
      allow(described_class).to receive(:_weigh).and_return(1)
      recs = [results.last]
      items = described_class.send(:_results_to_response, term: 'example', results: JSON.parse(recs.to_json))
      expect(items.first[:title]).to eql(recs.first[:name])
      expect(items.first[:weight]).to be(1)
      expect(items.first[:description]).to be_nil
      expect(items.first[:url]).to be_nil
      expect(items.first[:dmproadmap_host_id]).to be_nil
    end

    it 'returns what we expect when the record has all data elements' do
      allow(described_class).to receive(:_weigh).and_return(1)
      recs = [results.first]
      items = described_class.send(:_results_to_response, term: 'example', results: JSON.parse(recs.to_json))
      expect(items.first[:title]).to eql(recs.first[:name])
      expect(items.first[:weight]).to be(1)
      expect(items.first[:description]).to eql(recs.first[:description])
      expect(items.first[:url]).to eql(recs.first[:homepage])
      expected = { identifier: recs.first[:uri], type: 'url' }
      expect(items.first[:dmproadmap_host_id]).to eql(expected)
    end

    it 'sorts the results based on weight and name' do
      recs = [results.first, results.last]
      allow(described_class).to receive(:_weigh).with(term: 'repo', repo: JSON.parse(recs.first.to_json))
                                                .and_return(0)
      allow(described_class).to receive(:_weigh).with(term: 'repo', repo: JSON.parse(recs.last.to_json))
                                                .and_return(5)
      items = described_class.send(:_results_to_response, term: 'repo', results: JSON.parse(recs.to_json))
      expect(items.first[:title]).to eql(recs.last[:name])
      expect(items.last[:title]).to eql(recs.first[:name])
    end
  end

  describe '_weigh(term:, repo:)' do
    let!(:repo) do
      { name: 'example university', description: 'foo bar', homepage: 'http://foo.bar', uri: 'https://bar.foo' }
    end

    it 'returns zero if :term is not a String' do
      expect(described_class.send(:_weigh, term: 123, repo: repo)).to be(0)
    end

    it 'returns zero if :repo is not a Hash' do
      expect(described_class.send(:_weigh, term: '123', repo: 123)).to be(0)
    end

    it 'returns zero if repo:name is not a String' do
      expect(described_class.send(:_weigh, term: '123', repo: { foo: 'foo' })).to be(0)
    end

    it 'applies the correct score when we have a description match' do
      expect(described_class.send(:_weigh, term: 'foo bar', repo: JSON.parse(repo.to_json))).to be(1)
    end

    it 'applies the correct score when we have an homepage match' do
      expect(described_class.send(:_weigh, term: 'foo.bar', repo: JSON.parse(repo.to_json))).to be(1)
    end

    it 'applies the correct score when we have a partial name match' do
      expect(described_class.send(:_weigh, term: 'xample', repo: JSON.parse(repo.to_json))).to be(1)
    end

    it 'applies the correct score when we have a starts with name match' do
      expect(described_class.send(:_weigh, term: 'exam', repo: JSON.parse(repo.to_json))).to be(2)
    end

    it 'is possible to have a score of zero' do
      expect(described_class.send(:_weigh, term: 'repository', repo: JSON.parse(repo.to_json))).to be(0)
    end

    it 'is possible to get a score of 3' do
      repo[:description] = 'A good example'
      repo[:homepage] = 'https://xam.edu/foo'
      expect(described_class.send(:_weigh, term: 'xam', repo: JSON.parse(repo.to_json))).to be(3)
    end

    it 'is possible to get a score of 5 (highest score)' do
      repo[:description] = 'A good example'
      repo[:homepage] = 'https://exam.edu/foo'
      expect(described_class.send(:_weigh, term: 'exam', repo: JSON.parse(repo.to_json))).to be(4)
    end
  end
end
