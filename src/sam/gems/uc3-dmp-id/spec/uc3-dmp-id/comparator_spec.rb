# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Comparator' do
  let!(:dmp) { mock_dmp }

  let!(:ror) { 'https://ror.org/01cwqze88' }
  let!(:fundref) { 'https://doi.org/10.13039/100000002' }

  let!(:described_class) { Uc3DmpId::Comparator.new(dmp: mock_dmp) }
  let!(:response) { { score: 0, notes: [] } }

  context 'when initializing with valid arguments' do
    it 'sets the dmp attribute' do
      comparator = Uc3DmpId::Comparator.new(dmp:)
      expect(comparator.dmp).to eq(dmp['dmp'])
    end
  end

  context 'when initializing with missing or empty DMP' do
    it 'raises a ComparatorError' do
      expect do
        Uc3DmpId::Comparator.new(dmp: {})
      end.to raise_error(Uc3DmpId::ComparatorError, 'No DMP or the DMP did not contain enough information to use.')
    end
  end

  describe 'compare(hash:)' do
    it 'returns a default response if :hash is not a Hash' do
      result = described_class.compare(hash: 123)
      expect(result[:confidence]).to eql('None')
      expect(result[:score]).to be(0)
      expect(result[:notes]).to eql([])
    end

    it 'returns a default response if :hash does not contain a :title' do
      result = described_class.compare(hash: { contact: {} })
      expect(result[:confidence]).to eql('None')
      expect(result[:score]).to be(0)
      expect(result[:notes]).to eql([])
    end

    it 'returns the expected response when the grant IDs match' do
      described_class.details_hash[:grant_ids] = ['foo']
      hash = JSON.parse({ title: 'Foo test', fundings: [{ grant: ['FoO'] }] }.to_json)
      result = described_class.compare(hash:)
      expect(result[:confidence]).to eql('Absolute')
      expect(result[:score]).to be(100)
      expect(result[:notes]).to eql(['the grant ID matched'])
    end
  end

  describe '_extract_dmp_details(dmp:)' do
    it 'returns nil if :dmp is not a Hash' do
      expect(described_class.send(:_extract_dmp_details, dmp: 123)).to be_nil
    end

    it 'returns nil if :dmp does not have a :title' do
      expect(described_class.send(:_extract_dmp_details, dmp: JSON.parse({ contact: 'foo' }.to_json))).to be_nil
    end

    it 'returns nil if :dmp does not have a :contact' do
      expect(described_class.send(:_extract_dmp_details, dmp: JSON.parse({ title: 'foo' }.to_json))).to be_nil
    end

    # rubocop:disable RSpec/ExampleLength
    it 'sets the appropriate defaults' do
      hash = JSON.parse({ title: '  Foo bar baz   ', contact: {} }.to_json)

      expected = {
        created: Time.now.iso8601,
        title: 'foo bar baz',
        abstract: nil,
        keywords: [],
        identifiers: [],
        last_names: [],
        affiliation_ids: [],
        affiliations: [],
        funder_names: [],
        funder_ids: [],
        opportunity_ids: [],
        grant_ids: [],
        repositories: []
      }
      described_class.send(:_extract_dmp_details, dmp: hash)
      expect(described_class.details_hash).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'correctly converts the mock DMP' do
      contact = {
        name: 'Doe, Jane',
        contact_id: { type: 'orcid', identifier: 'DOE-orcid' },
        dmproadmap_affiliation: {
          name: 'University of Foo',
          affiliation_id: { type: 'ror', identifier: ror }
        }
      }
      contributors = [
        {
          name: 'Smith, Adam',
          contributor_id: { type: 'orcid', identifier: 'SMITH-orcid' },
          role: ['player 1'],
          dmproadmap_affiliation: {
            name: 'Foo College',
            affiliation_id: { type: 'ror', identifier: 'SMITH-ror' }
          }
        }, {
          name: 'DREW, NANCY   ',
          contributor_id: { type: 'orcid', identifier: 'DRew-orcid' },
          role: ['player 2']
        }
      ]
      fundings = [
        {
          name: 'The Foo Funders',
          funder_id: { type: 'ror', identifier: ror },
          funding_status: 'granted',
          dmproadmap_funding_opportunity_id: { type: 'other', identifier: 'hhhhhh' },
          grant_id: { type: 'url', identifier: 'http://award.show.org/grant/88888' }
        }, {
          name: 'The Other Funder',
          funder_id: { type: 'fundref', identifier: 'OTHER-fundref' },
          funding_status: 'planned',
          dmproadmap_funding_opportunity_id: { type: 'other', identifier: 'gggggg' }
        }
      ]
      datasets = [
        {
          title: 'Sample one',
          distribution: [
            { host: { name: 'Repo one', url: 'htps://repo.one', dmproadmap_host_id: { identifier: 'REPO-1' } } }
          ],
          keyword: %w[sample one]
        }, {
          title: 'Sample two',
          distribution: [{ host: { name: 'Repo two', url: 'htps://repo.two' } }],
          keyword: %w[sample two]
        }
      ]

      hash = JSON.parse({
        created: (Time.now - 100_000).iso8601,
        title: '  Foo bar baz   ',
        description: '  Lorem ipsum is psuedo text for this DMP.</p>',
        dmp_id: { type: 'doi', identifier: 'https://doi.org/10.11111/AAA999' },
        contact:,
        contributor: contributors,
        project: [{ funding: fundings }],
        dataset: datasets
      }.to_json)

      expected = {
        created: hash['created'],
        title: hash['title'].downcase.strip,
        abstract: hash['description'].downcase.strip,
        keywords: %w[sample one two],
        identifiers: [
          hash['dmp_id']['identifier'],
          'doe-orcid', ror, 'smith-orcid', 'smith-ror', 'drew-orcid',
          fundref, 'http://award.show.org/grant/88888', '88888', 'hhhhhh',
          'other-fundref', 'gggggg',
          'htps://repo.one', 'repo-1', 'htps://repo.two'
        ],
        last_names: %w[doe smith drew],
        affiliation_ids: [ror, 'smith-ror'],
        affiliations: ['university of foo', 'foo college'],
        funder_names: ['the foo funders', 'the other funder'],
        funder_ids: [fundref, 'other-fundref'],
        opportunity_ids: %w[hhhhhh gggggg],
        grant_ids: ['http://award.show.org/grant/88888', '88888'],
        repositories: ['repo one', 'repo two']
      }

      described_class.send(:_extract_dmp_details, dmp: hash)
      expect(described_class.details_hash).to eql(expected)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '_extract_funding(array:)' do
    let!(:array) do
      JSON.parse([{
        name: 'The Foo Funders',
        funding_status: 'granted',
        grant_id: { type: 'url', identifier: 'http://awards.foo.org/foo-12345-award' },
        dmproadmap_funding_opportunity_id: { type: 'other', identifier: 'FOO-98765' },
        funder_id: { type: 'ror', identifier: ror }
      }].to_json)
    end

    it 'returns an empty Array if :array is not an Array' do
      expect(described_class.send(:_extract_funding, array: 123)).to eql([])
    end

    it 'returns an empty Array if :array is empty' do
      expect(described_class.send(:_extract_funding, array: [])).to eql([])
    end

    # rubocop:disable RSpec/MultipleExpectations
    it 'ignores entries in :array that are not a Hash' do
      fundings = ['zzzzzzzz']
      expect(described_class.send(:_extract_funding, array: fundings)).to eql(fundings)
      expect(described_class.details_hash[:identifiers].include?(fundings.first)).to be(false)
      expect(described_class.details_hash[:funder_names].include?(fundings.first)).to be(false)
      expect(described_class.details_hash[:funder_ids].include?(fundings.first)).to be(false)
      expect(described_class.details_hash[:opportunity_ids].include?(fundings.first)).to be(false)
      expect(described_class.details_hash[:grant_ids].include?(fundings.first)).to be(false)
    end
    # rubocop:enable RSpec/MultipleExpectations

    it 'adds the :funder_id and :opportunity_id and :grant_id to the @details_hash[:identifiers] array' do
      expect(described_class.send(:_extract_funding, array:)).to eql(array)
      expect(described_class.details_hash[:identifiers].include?('http://awards.foo.org/foo-12345-award')).to be(true)
      expect(described_class.details_hash[:identifiers].include?('foo-12345-award')).to be(true)
      expect(described_class.details_hash[:identifiers].include?('foo-98765')).to be(true)
      expect(described_class.details_hash[:identifiers].include?(ror)).to be(true)
    end

    it 'adds the Crossref Funder id if the :funder_id provided was a ROR' do
      expect(described_class.send(:_extract_funding, array:)).to eql(array)
      expect(described_class.details_hash[:funder_ids].include?(fundref)).to be(true)
    end

    it 'adds the funder name, opportunity number and grant to their respective arrays' do
      expect(described_class.send(:_extract_funding, array:)).to eql(array)
      expect(described_class.details_hash[:funder_names].include?('the foo funders')).to be(true)
      expect(described_class.details_hash[:opportunity_ids].include?('foo-98765')).to be(true)
      expected = ['http://awards.foo.org/foo-12345-award', 'foo-12345-award']
      expect(described_class.details_hash[:grant_ids].include?(expected)).to be(true)
    end
  end

  describe '_extract_people(array:)' do
    let!(:array) do
      affil = { name: 'Foo Univ.', affiliation_id: { type: 'ror', identifier: 'yyyyyyyy' } }

      JSON.parse([
        { name: 'Contact Foo', contact_id: { type: 'orcid', identifier: 'zzzz' }, dmproadmap_affiliation: affil },
        { name: 'Bar, Contrib', contact_id: { type: 'orcid', identifier: 'xxxx' }, dmproadmap_affiliation: affil }
      ].to_json)
    end

    it 'returns an empty Array if :array is not an Array' do
      expect(described_class.send(:_extract_people, array: 123)).to eql([])
    end

    it 'returns an empty Array if :array is empty' do
      expect(described_class.send(:_extract_people, array: [])).to eql([])
    end

    it 'ignores entries in :array that are not a Hash' do
      people = ['zzzzzzzz']
      expect(described_class.send(:_extract_people, array: people)).to eql(people)
      expect(described_class.details_hash[:identifiers].include?(people.first)).to be(false)
      expect(described_class.details_hash[:last_names].include?(people.first)).to be(false)
      expect(described_class.details_hash[:affiliation_ids].include?(people.first)).to be(false)
      expect(described_class.details_hash[:affiliations].include?(people.first)).to be(false)
    end

    it 'adds the :id and :ror to the @details_hash[:identifiers] array' do
      expect(described_class.send(:_extract_people, array:)).to eql(array)
      expect(described_class.details_hash[:identifiers].include?(%w[zzzz yyyyyyyy])).to be(true)
      expect(described_class.details_hash[:identifiers].include?(%w[xxxx yyyyyyyy])).to be(true)
    end

    it 'adds the last names to the @details_hash[:last_names] array' do
      expect(described_class.send(:_extract_people, array:)).to eql(array)
      expect(described_class.details_hash[:last_names].include?('foo')).to be(true)
      expect(described_class.details_hash[:last_names].include?('bar')).to be(true)
    end

    it 'adds the affiliation names to the @details_hash[:affiliations_ids] array' do
      expect(described_class.send(:_extract_people, array:)).to eql(array)
      expect(described_class.details_hash[:affiliation_ids].include?('yyyyyyyy')).to be(true)
    end

    it 'adds the affiliation names to the @details_hash[:affiliations] array' do
      expect(described_class.send(:_extract_people, array:)).to eql(array)
      expect(described_class.details_hash[:affiliations].include?('foo univ.')).to be(true)
    end
  end

  describe '_extract_repositories(repos:, logger:)' do
    it 'returns an empty Array if :repos is not an Array' do
      expect(described_class.send(:_extract_repositories, repos: 123)).to eql([])
    end

    it 'returns an empty Array if :repos is empty' do
      expect(described_class.send(:_extract_repositories, repos: [])).to eql([])
    end

    it 'ignores entries in :repos that are not a Hash' do
      repos = ['zzzzzzzz']
      expect(described_class.send(:_extract_repositories, repos:)).to eql(repos)
      expect(described_class.details_hash[:identifiers].include?(repos.first)).to be(false)
      expect(described_class.details_hash[:repositories].include?(repos.first)).to be(false)
    end

    it 'adds the :url and :dmproadmap_host_id to the @details_hash[:identifiers] array' do
      repos = JSON.parse([
        { name: 'Foo Repository', url: 'http://repo.foo.org', dmproadmap_host_id: { identifier: 'zzzzzzzz' } }
      ].to_json)
      expect(described_class.send(:_extract_repositories, repos:)).to eql(repos)
      expect(described_class.details_hash[:identifiers].include?(repos.first['name'].downcase)).to be(false)
      expected = [repos.first['url'], repos.first['dmproadmap_host_id']['identifier']]
      expect(described_class.details_hash[:identifiers].include?(expected)).to be(true)
    end

    it 'adds the :name to the @details_hash[:repositories] array' do
      repos = JSON.parse([
        { name: 'Foo Repository', url: 'http://repo.foo.org', dmproadmap_host_id: { identifier: 'zzzzzzzz' } }
      ].to_json)
      expect(described_class.send(:_extract_repositories, repos:)).to eql(repos)
      expect(described_class.details_hash[:repositories].include?(repos.first['name'].downcase)).to be(true)
      unexpected = [repos.first['url'], repos.first['dmproadmap_host_id']['identifier']]
      expect(described_class.details_hash[:repositories].include?(unexpected)).to be(false)
    end
  end

  describe '_grants_match?(array:, response:)' do
    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_grants_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_grants_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no matches' do
      orcids = ['https://orcid.org/foo-bar-baz']
      expect(described_class.send(:_grants_match?, array: orcids, response:)).to eql(response)
    end

    it 'increments the response[:score] by 100 and adds a :note and :confidence if one of the grant ids matched' do
      fundings = JSON.parse(
        [{ id: 'https://doi.org/foo', name: 'Foo', grant: ['zzzzzzzz', 'http://foo.bar/543'] }].to_json
      )
      described_class.details_hash[:grant_ids] << 'zzzzzzzz'
      result = described_class.send(:_grants_match?, array: fundings, response:)
      expect(result[:score]).to be(100)
      expect(result[:confidence]).to eql('Absolute')
      expect(result[:notes].include?('the grant ID matched')).to be(true)
    end
  end

  describe '_opportunities_match?(array:, response:)' do
    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_opportunities_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_opportunities_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no matches' do
      orcids = ['https://orcid.org/foo-bar-baz']
      expect(described_class.send(:_opportunities_match?, array: orcids, response:)).to eql(response)
    end

    it 'increments the response[:score] by 5 and adds a :note if one of the grant ids match the opportunity' do
      fundings = JSON.parse([
        { id: 'https://doi.org/foo', name: 'Foo', grant: ['zzzzzzzz', 'http://foo.bar/543'] }
      ].to_json)
      described_class.details_hash[:opportunity_ids] << 'zzzzzzzz'
      result = described_class.send(:_opportunities_match?, array: fundings, response:)
      expect(result[:score]).to be(5)
      expect(result[:notes].include?('the funding opportunity number matched')).to be(true)
    end
  end

  describe '_orcids_match?(array:, response:)' do
    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_orcids_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_orcids_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no matches' do
      orcids = ['https://orcid.org/foo-bar-baz']
      expect(described_class.send(:_orcids_match?, array: orcids, response:)).to eql(response)
    end

    it 'increments the response[:score] by 2 and adds a :note if one of the ORCIDs match' do
      orcids = JSON.parse([{ id: 'https://orcid.org/foo-bar-baz' }, { id: 'https://orcid.org/baz-bar-foo' }].to_json)
      described_class.details_hash[:identifiers] << orcids.last['id']
      result = described_class.send(:_orcids_match?, array: orcids, response:)
      expect(result[:score]).to be(2)
      expect(result[:notes].include?('contributor ORCIDs matched')).to be(true)
    end

    it 'increments the response[:score] by 2 * the number of ORCIDs matched' do
      orcids = JSON.parse([{ id: 'https://orcid.org/foo-bar-baz' }, { id: 'https://orcid.org/baz-bar-foo' }].to_json)
      described_class.details_hash[:identifiers] << orcids.first['id']
      described_class.details_hash[:identifiers] << orcids.last['id']
      result = described_class.send(:_orcids_match?, array: orcids, response:)
      expect(result[:score]).to be(4)
      expect(result[:notes].include?('contributor ORCIDs matched')).to be(true)
    end
  end

  describe '_last_name_and_affiliation_match?(array:, response:)' do
    let!(:people) do
      JSON.parse([
        { id: 'https://orcid.org/foo', last_name: 'Foo', affiliation: { id: 'foo.edu', name: 'Univ. of Foo' } },
        { id: 'https://orcid.org/bar', last_name: 'Bar', affiliation: { id: 'bar.edu', name: 'Bar College' } },
        { id: 'https://orcid.org/baz', last_name: 'Baz', affiliation: { id: 'baz.edu', name: 'Baz Univ.' } }
      ].to_json)
    end

    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_last_name_and_affiliation_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_last_name_and_affiliation_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no last_name, affiliation name or ROR matches' do
      described_class.details_hash[:last_names] = %w[do re mi]
      described_class.details_hash[:affiliation_ids] = %w[99999 88888]
      described_class.details_hash[:affiliations] = ['example univ.', 'test college']
      expect(described_class.send(:_last_name_and_affiliation_match?, array: people, response:)).to eql(response)
    end

    it 'increments the response[:score] by 1 and adds a :note if one of the last_names match' do
      described_class.details_hash[:last_names] = %w[do foo mi]
      described_class.details_hash[:affiliation_ids] = %w[99999 88888]
      described_class.details_hash[:affiliations] = ['example univ.', 'test college']
      result = described_class.send(:_last_name_and_affiliation_match?, array: people, response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('contributor names and affiliations matched')).to be(true)
    end

    it 'increments the response[:score] by 1 and adds a :note if one of the affiliation names match' do
      described_class.details_hash[:last_names] = %w[do rei mi]
      described_class.details_hash[:affiliation_ids] = %w[99999 88888]
      described_class.details_hash[:affiliations] = ['baz univ.', 'test college']
      result = described_class.send(:_last_name_and_affiliation_match?, array: people, response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('contributor names and affiliations matched')).to be(true)
    end

    it 'increments the response[:score] by 1 and adds a :note if one of the RORs match' do
      described_class.details_hash[:last_names] = %w[do rei mi]
      described_class.details_hash[:affiliation_ids] = ['99999', 'foo.edu']
      described_class.details_hash[:affiliations] = ['example univ.', 'test college']
      result = described_class.send(:_last_name_and_affiliation_match?, array: people, response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('contributor names and affiliations matched')).to be(true)
    end

    it 'increments the response[:score] by the number of positive matches' do
      described_class.details_hash[:last_names] = %w[do foo mi]
      described_class.details_hash[:affiliation_ids] = ['bar.edu', 'foo.edu']
      described_class.details_hash[:affiliations] = ['baz univ.', 'test college']
      result = described_class.send(:_last_name_and_affiliation_match?, array: people, response:)
      expect(result[:score]).to be(4)
      expect(result[:notes].include?('contributor names and affiliations matched')).to be(true)
    end
  end

  describe '_repository_match?(array:, response:)' do
    let!(:repos) do
      JSON.parse([{ id: ['foo'] }, { id: %w[bar 12345] }, { id: ['baz', 'http://baz.edu'] }].to_json)
    end

    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_repository_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_repository_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no keyword matches' do
      expect(described_class.send(:_repository_match?, array: ['zzzzzzzzzz'], response:)).to eql(response)
    end

    it 'increments the response[:score] by 1 and adds a :note if one of the repositories match' do
      described_class.details_hash[:identifiers] = described_class.details_hash[:identifiers] + ['foo']
      result = described_class.send(:_repository_match?, array: repos, response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('repositories matched')).to be(true)
    end

    it 'increments the response[:score] by 1 and adds a :note if only some of the repositories match' do
      described_class.details_hash[:identifiers] = described_class.details_hash[:identifiers] + %w[foo 12345]
      result = described_class.send(:_repository_match?, array: repos, response:)
      expect(result[:score]).to be(2)
      expect(result[:notes].include?('repositories matched')).to be(true)
    end
  end

  describe '_keyword_match?(array:, response:)' do
    let!(:keywords) { %w[foo bar baz] }

    it 'returns :response as-is if :array is not an Array' do
      expect(described_class.send(:_keyword_match?, array: '123', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_keyword_match?, array: ['foo'], response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if there are no keyword matches' do
      expect(described_class.send(:_keyword_match?, array: ['zzzzzzzzzz'], response:)).to eql(response)
    end

    it 'increments the response[:score] by 1 and adds a :note if ALL of the keywords match' do
      described_class.details_hash[:keywords] = keywords
      result = described_class.send(:_keyword_match?, array: keywords, response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('keywords matched')).to be(true)
    end

    it 'increments the response[:score] by 1 and adds a :note if only some of the keywords match' do
      described_class.details_hash[:keywords] = keywords
      result = described_class.send(:_keyword_match?, array: ['foo'], response:)
      expect(result[:score]).to be(1)
      expect(result[:notes].include?('keywords matched')).to be(true)
    end
  end

  describe '_text_match?(type:, text:, response:)' do
    it 'returns the :response as-is if :abstract is not a Strings' do
      expect(described_class.send(:_text_match?, text: [123], response:)).to eql(response)
    end

    it 'returns the :response as-is if :abstract is empty' do
      expect(described_class.send(:_text_match?, text: '   ', response:)).to eql(response)
    end

    it 'returns the :response as-is if :response is not a Hash' do
      expect(described_class.send(:_text_match?, text: 'foo', response: 'bar')).to eql('bar')
    end

    it 'returns the :response as-is if :type is not a valid text type of the DMP' do
      expect(described_class.send(:_text_match?, type: 'foo', text: 'bar', response:)).to eql(response)
    end

    it 'returns the :response as-is if the score of the NLP comparison of :text is less than 0.5' do
      expect(described_class.send(:_text_match?, text: 'gggggg hhhhhhhh', response:)).to eql(response)
    end

    it 'increments the response[:score] by 2 if the NLP comparison of :text is between 0.5 and 0.75' do
      words = dmp['dmp']['project'].first['description'].split
      abstract = words.join(' ').gsub(words.first, 'Foo')
      abstract = abstract[0..abstract.length - 6]

      result = described_class.send(:_text_match?, type: 'abstract', text: abstract, response:)
      expect(result[:score]).to be(2)
      expect(result[:notes].include?('abstracts are similar')).to be(true)
    end

    it 'increments the response[:score] by 5 if the NLP comparison of :text is better than 0.75' do
      words = dmp['dmp']['project'].first['title'].split
      abstract = words.join(' ').gsub(words.first, 'Foo')

      result = described_class.send(:_text_match?, type: 'title', text: abstract, response:)
      expect(result[:score]).to be(5)
      expect(result[:notes].include?('titles are similar')).to be(true)
    end
  end

  describe '_cleanse_text(text:)' do
    it 'returns nil unless :text is a String' do
      expect(described_class.send(:_cleanse_text, text: 123)).to be_nil
    end

    it 'converts the :text to lower case and removes leading/trailing spaces' do
      text = '   Foo BAr  '
      expect(described_class.send(:_cleanse_text, text:)).to eql('foo bar')
    end

    it 'removes any words that are part of the STOP_WORDS list' do
      text = 'The   Foo BAr and baz '
      expect(described_class.send(:_cleanse_text, text:)).to eql('foo bar baz')
    end
  end

  describe '_compare_arrays(array_a: [], array_b: [])' do
    it 'returns 0 if array_a is not an Array' do
      expect(described_class.send(:_compare_arrays, array_a: 'foo', array_b: %w[foo bar])).to be(0)
    end

    it 'returns 0 if array_b is not an Array' do
      expect(described_class.send(:_compare_arrays, array_a: %w[foo bar], array_b: 'foo')).to be(0)
    end

    it 'returns 0 if there are no matches' do
      expect(described_class.send(:_compare_arrays, array_a: %w[foo bar], array_b: %w[abc 123])).to be(0)
    end

    it 'returns the number of matches' do
      expect(described_class.send(:_compare_arrays, array_a: %w[foo bar], array_b: %w[abc 123 foo bar])).to be(2)
    end
  end
end
