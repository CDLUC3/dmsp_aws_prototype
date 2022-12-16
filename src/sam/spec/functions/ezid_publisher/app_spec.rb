# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Functions::EzidPublisher' do
  let!(:dmp_id) { mock_dmp_id }
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmp) do
    json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))['dmp']
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse(prov.to_json), p_key: p_key, json: json)
  end
  let!(:event) do
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    ev = aws_sns_event
    ev['Records'].first['Sns']['Message'] = JSON.parse({ action: 'create', provenance: prov[:PK], dmp: p_key }.to_json)
    ev
  end
  let!(:described_class) { Functions::EzidPublisher }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_dynamodb(item_array: [dmp])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return(mock_url)
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    resp = JSON.parse({ status: 200, items: prov }.to_json)
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_lambda_cotext).and_return(resp)
  end

  describe 'process(event:, context:)' do
    it 'returns a 400 when the AWS event did not contain a :message' do
      event['Records'].first['Sns'].delete('Message')
      described_class.process(event: event, context: aws_context)
      event.delete('Message')
      expect(Responder).to have_received(:respond).with(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
    end

    it 'returns a 400 when the :message did not contain an :action' do
      event['Records'].first['Sns']['Message'] = { dmp: 'foo', provenance: 'bar' }.to_json
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
    end

    it 'returns a 400 when the :message did not contain a :provenance' do
      event['Records'].first['Sns']['Message'] = { dmp: 'foo', action: 'bar' }.to_json
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
    end

    it 'returns a 400 when the :message did not contain a :dmp' do
      event['Records'].first['Sns']['Message'] = { action: 'foo', provenance: 'bar' }.to_json
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
    end

    it 'returns a 404 if the DMP could not be found' do
      allow(described_class).to receive(:load_dmp).and_return(nil)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 404, errors: Messages::MSG_DMP_NOT_FOUND, event: event)
    end

    it 'returns a 500 if EZID did not return a 200 or 201 status' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      mock_httparty(code: 400)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 500, errors: "#{Messages::MSG_EZID_FAILURE} - 400",
                                                        event: event)
    end

    it 'returns a 200 when successful' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      mock_httparty(code: 200)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 200, errors: Messages::MSG_SUCCESS, event: event)
    end

    it 'returns a 500 when the :message was not parseable JSON' do
      allow(JSON).to receive(:parse).and_raise(JSON::ParserError)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 500, errors: Messages::MSG_INVALID_JSON, event: event)
    end

    it 'returns a 500 when there is a standard error' do
      allow(described_class).to receive(:load_dmp).and_raise(StandardError)
      result = described_class.process(event: event, context: aws_context)
      expect(Responder).not_to have_received(:respond)
      expect(result[:statusCode]).to be(500)
      expect(JSON.parse(result[:body])['errors']).to eql([Messages::MSG_SERVER_ERROR])
    end

    it 'returns a 500 when there is a server error' do
      allow(described_class).to receive(:load_dmp).and_raise(aws_error)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 500, errors: "#{Messages::MSG_SERVER_ERROR} - Testing",
                                                        event: event)
    end
  end

  describe 'private methods' do
    describe 'load_dmp(provenance_pk:, dmp_pk:, table:, client:, debug:)' do
      let!(:dmp_pk) { "#{KeyHelper::PK_DMP_PREFIX}#{dmp_id}" }

      it 'returns nil if :provenance_pk is nil' do
        result = described_class.send(:load_dmp, provenance_pk: nil, dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :dmp_pk is nil' do
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: nil, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :table is nil' do
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: dmp_pk, table: nil, client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :client is nil' do
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: dmp_pk, table: 'foo', client: nil)
        expect(result).to be_nil
      end

      it 'returns nil if Provenance could not be found' do
        allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_pk).and_return({ status: 404 })
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if DMP could not be found' do
        allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_pk).and_return({ status: 200,
                                                                                             items: [prov] })
        allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 404 })
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns the DMP' do
        allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_pk).and_return({ status: 200,
                                                                                             items: [prov] })
        expected = { status: 200, items: [JSON.parse({ dmp: dmp }.to_json)] }
        allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return(expected)
        result = described_class.send(:load_dmp, provenance_pk: prov[:PK], dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to eql(dmp)
      end
    end

    describe 'dmp_to_datacite_xml(dmp_id:, dmp:)' do
      let!(:xml_open) do
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
            <resource xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://datacite.org/schema/kernel-4" xsi:schemaLocation="http://datacite.org/schema/kernel-4 http://schema.datacite.org/meta/kernel-4.4/metadata.xsd">
              <identifier identifierType="DOI">#{dmp_id.match(KeyHelper::DOI_REGEX)}</identifier>
              <creators>
                <creator>
                  <creatorName nameType="Personal">#{dmp['contact']['name']}</creatorName>
                  <nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
                    #{dmp['contact']['contact_id']['identifier']}
                  </nameIdentifier>
                  <affiliation affiliationIdentifier="#{dmp['contact']['dmproadmap_affiliation']['affiliation_id']['identifier']}" affiliationIdentifierScheme="ROR">
                    #{dmp['contact']['dmproadmap_affiliation']['name'].to_s.gsub(/\(.*\)\s?$/, '').strip}
                  </affiliation>
                </creator>
              </creators>
              <titles>
                <title xml:lang="en-US">#{dmp['title']}</title>
              </titles>
              <publisher xml:lang="en-US">#{described_class::APPLICATION_NAME}</publisher>
              <publicationYear>#{Time.now.year}</publicationYear>
              <language>en</language>
              <resourceType resourceTypeGeneral="OutputManagementPlan">#{described_class::DEFAULT_RESOURCE_TYPE}</resourceType>
              <descriptions>
                <description xml:lang="en" descriptionType="Abstract">
                  #{dmp['description']}
                </description>
              </descriptions>
        XML
      end
      let!(:xml_producer) do
        <<~XML
          #{described_class::TAB * 2}<contributors>
          #{described_class::TAB * 3}<contributor contributorType="Producer">
          #{described_class::TAB * 4}<contributorName nameType="Organizational">Example University</contributorName>
          #{described_class::TAB * 4}<nameIdentifier schemeURI="https://ror.org/" nameIdentifierScheme="ROR">
          #{described_class::TAB * 5}https://ror.org/1234567890
          #{described_class::TAB * 4}</nameIdentifier>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 2}</contributors>
        XML
      end
      let!(:xml_close) do
        <<~XML
          #{described_class::TAB}</resource>
        XML
      end

      it 'returns expected XML when there are no contributors, fundings or related_identifiers' do
        dmp.delete('contributor')
        dmp['project'].first.delete('funding')
        dmp.delete('dmproadmap_sponsors')
        dmp.delete('dmproadmap_related_identifiers')
        expected = xml_open + xml_producer + xml_close
        result = described_class.send(:dmp_to_datacite_xml, dmp_id: dmp_id, dmp: dmp)
        expect(result).to eql(expected)
      end

      it 'returns expected XML when there are no contributors or related_identifiers' do
        dmp.delete('contributor')
        dmp.delete('dmproadmap_sponsors')
        dmp.delete('dmproadmap_related_identifiers')
        expected = xml_open + xml_producer
        expected += <<~XML
          #{described_class::TAB * 2}<fundingReferences>
          #{described_class::TAB * 3}<fundingReference>
          #{described_class::TAB * 4}<funderName>National Funding Organization</funderName>
          #{described_class::TAB * 4}<funderIdentifier funderIdentifierType="Crossref Funder ID">http://dx.doi.org/10.13039/100005595</funderIdentifier>
          #{described_class::TAB * 3}</fundingReference>
          #{described_class::TAB * 2}</fundingReferences>
        XML
        expected += xml_close
        result = described_class.send(:dmp_to_datacite_xml, dmp_id: dmp_id, dmp: dmp)
        expect(result).to eql(expected)
      end

      it 'returns expected XML when there are no contributors, fundings' do
        dmp.delete('contributor')
        dmp.delete('dmproadmap_sponsors')
        dmp['project'].first.delete('funding')
        expected = xml_open + xml_producer
        expected += <<~XML
          #{described_class::TAB * 2}<relatedIdentifiers>
          #{described_class::TAB * 3}<relatedIdentifier relationType="Cites" relatedIdentifierType="DOI">
          #{described_class::TAB * 4}https://doi.org/10.21966/1.566666
          #{described_class::TAB * 3}</relatedIdentifier>
          #{described_class::TAB * 3}<relatedIdentifier relationType="IsReferencedBy" relatedIdentifierType="URL">
          #{described_class::TAB * 4}10.1111/fog.12471
          #{described_class::TAB * 3}</relatedIdentifier>
          #{described_class::TAB * 2}</relatedIdentifiers>
        XML
        expected += xml_close
        result = described_class.send(:dmp_to_datacite_xml, dmp_id: dmp_id, dmp: dmp)
        expect(result).to eql(expected)
      end

      it 'returns expected XML' do
        expected = xml_open
        expected += <<~XML
          #{described_class::TAB * 2}<contributors>
          #{described_class::TAB * 3}<contributor contributorType="Producer">
          #{described_class::TAB * 4}<contributorName nameType="Organizational">Example University</contributorName>
          #{described_class::TAB * 4}<nameIdentifier schemeURI="https://ror.org/" nameIdentifierScheme="ROR">
          #{described_class::TAB * 5}https://ror.org/1234567890
          #{described_class::TAB * 4}</nameIdentifier>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 3}<contributor contributorType="ProjectLeader">
          #{described_class::TAB * 4}<contributorName nameType="Personal">Jane Doe</contributorName>
          #{described_class::TAB * 4}<nameIdentifier schemeURI="https://orcid.org/" nameIdentifierScheme="ORCID">
          #{described_class::TAB * 5}https://orcid.org/0000-0000-0000-000X
          #{described_class::TAB * 4}</nameIdentifier>
          #{described_class::TAB * 4}<affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
          #{described_class::TAB * 5}Example University
          #{described_class::TAB * 4}</affiliation>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 3}<contributor contributorType="ProjectLeader">
          #{described_class::TAB * 4}<contributorName nameType="Personal">Jennifer Smith</contributorName>
          #{described_class::TAB * 4}<affiliation affiliationIdentifier="https://ror.org/0987654321" affiliationIdentifierScheme="ROR">
          #{described_class::TAB * 5}University of Somewhere
          #{described_class::TAB * 4}</affiliation>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 3}<contributor contributorType="ProjectLeader">
          #{described_class::TAB * 4}<contributorName nameType="Personal">Sarah James</contributorName>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 3}<contributor contributorType="Sponsor">
          #{described_class::TAB * 4}<contributorName nameType="Organizational">Example Lab</contributorName>
          #{described_class::TAB * 4}<nameIdentifier schemeURI="https://ror.org/" nameIdentifierScheme="ROR">
          #{described_class::TAB * 5}https://ror.org/abcdefg
          #{described_class::TAB * 4}</nameIdentifier>
          #{described_class::TAB * 3}</contributor>
          #{described_class::TAB * 2}</contributors>
          #{described_class::TAB * 2}<fundingReferences>
          #{described_class::TAB * 3}<fundingReference>
          #{described_class::TAB * 4}<funderName>National Funding Organization</funderName>
          #{described_class::TAB * 4}<funderIdentifier funderIdentifierType="Crossref Funder ID">http://dx.doi.org/10.13039/100005595</funderIdentifier>
          #{described_class::TAB * 3}</fundingReference>
          #{described_class::TAB * 2}</fundingReferences>
          #{described_class::TAB * 2}<relatedIdentifiers>
          #{described_class::TAB * 3}<relatedIdentifier relationType="Cites" relatedIdentifierType="DOI">
          #{described_class::TAB * 4}https://doi.org/10.21966/1.566666
          #{described_class::TAB * 3}</relatedIdentifier>
          #{described_class::TAB * 3}<relatedIdentifier relationType="IsReferencedBy" relatedIdentifierType="URL">
          #{described_class::TAB * 4}10.1111/fog.12471
          #{described_class::TAB * 3}</relatedIdentifier>
          #{described_class::TAB * 2}</relatedIdentifiers>
        XML
        expected += xml_close
        result = described_class.send(:dmp_to_datacite_xml, dmp_id: dmp_id, dmp: dmp)
        expect(result).to eql(expected)
      end
    end

    describe 'person_to_xml(json:, type:, tab_count:)' do
      let!(:json) do
        JSON.parse({
          name: 'Test Person',
          contributor_id: {
            type: 'orcid',
            identifier: 'https://orcid.org/0000-0000-0000-0000'
          },
          dmproadmap_affiliation: {
            name: 'Example University',
            affiliation_id: {
              type: 'ror',
              identifier: 'https://ror.org/1234567890'
            }
          },
          role: ['http://credit.niso.org/contributor-roles/data-curation']
        }.to_json)
      end

      it 'returns an empty string if json is not a Hash' do
        expect(described_class.send(:person_to_xml, json: 123)).to eql('')
      end

      it 'defaults the :type to ProjectLeader' do
        expected = <<~XML
          <contributor contributorType="ProjectLeader">
            <contributorName nameType="Personal">Test Person</contributorName>
            <nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
              https://orcid.org/0000-0000-0000-0000
            </nameIdentifier>
            <affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
              Example University
            </affiliation>
          </contributor>
        XML
        expect(described_class.send(:person_to_xml, json: json)).to eql(expected)
      end

      it 'uses the specified :type' do
        expected = <<~XML
          <contributor contributorType="Foo">
            <contributorName nameType="Personal">Test Person</contributorName>
            <nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
              https://orcid.org/0000-0000-0000-0000
            </nameIdentifier>
            <affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
              Example University
            </affiliation>
          </contributor>
        XML
        expect(described_class.send(:person_to_xml, json: json, type: 'Foo')).to eql(expected)
      end

      it 'skips the <nameIdentifier> if none was provided' do
        json.delete('contributor_id')
        expected = <<~XML
          <contributor contributorType="ProjectLeader">
            <contributorName nameType="Personal">Test Person</contributorName>
            <affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
              Example University
            </affiliation>
          </contributor>
        XML
        expect(described_class.send(:person_to_xml, json: json)).to eql(expected)
      end

      it 'skips the <affiliation> if none was provided' do
        json.delete('dmproadmap_affiliation')
        expected = <<~XML
          <contributor contributorType="ProjectLeader">
            <contributorName nameType="Personal">Test Person</contributorName>
            <nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
              https://orcid.org/0000-0000-0000-0000
            </nameIdentifier>
          </contributor>
        XML
        expect(described_class.send(:person_to_xml, json: json)).to eql(expected)
      end

      # rubocop:disable RSpec/ExampleLength
      it 'returns the expected XML for a Contact' do
        json['contact_id'] = json['contributor_id']
        json.delete('contributor_id')
        expected = <<~XML
          <creator>
            <creatorName nameType="Personal">Test Person</creatorName>
            <nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
              https://orcid.org/0000-0000-0000-0000
            </nameIdentifier>
            <affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
              Example University
            </affiliation>
          </creator>
        XML
        expect(described_class.send(:person_to_xml, json: json)).to eql(expected)
      end
      # rubocop:enable RSpec/ExampleLength

      it 'returns the expected XML when the json contains an :affiliation_id' do
        json['affiliation_id'] = JSON.parse({ type: 'url', identifier: 'http://example.com' }.to_json)
        json.delete('contributor_id')
        json.delete('dmproadmap_affiliation')
        json['name'] = 'Example University'
        expected = <<~XML
          <contributor contributorType="Sponsor">
            <contributorName nameType="Organizational">Example University</contributorName>
            <nameIdentifier>http://example.com</nameIdentifier>
          </contributor>
        XML
        expect(described_class.send(:person_to_xml, json: json, type: 'Sponsor')).to eql(expected)
      end

      it 'adheres to specified :tab_count' do
        tabs = described_class::TAB * 2
        expected = <<~XML
          #{tabs}<contributor contributorType="ProjectLeader">
          #{tabs}#{described_class::TAB}<contributorName nameType="Personal">Test Person</contributorName>
          #{tabs}#{described_class::TAB}<nameIdentifier schemeURI="#{described_class::SCHEMES[:orcid]}" nameIdentifierScheme="ORCID">
          #{tabs}#{described_class::TAB * 2}https://orcid.org/0000-0000-0000-0000
          #{tabs}#{described_class::TAB}</nameIdentifier>
          #{tabs}#{described_class::TAB}<affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
          #{tabs}#{described_class::TAB * 2}Example University
          #{tabs}#{described_class::TAB}</affiliation>
          #{tabs}</contributor>
        XML
        result = described_class.send(:person_to_xml, json: json, tab_count: 2)
        expect(result).to eql(expected)
      end
    end

    describe 'affiliation_to_xml(json:, tab_count: 0)' do
      let!(:json) do
        JSON.parse({
          name: 'Example University',
          affiliation_id: {
            type: 'ror',
            identifier: 'https://ror.org/1234567890'
          }
        }.to_json)
      end

      it 'returns an empty string if json is not a Hash' do
        expect(described_class.send(:affiliation_to_xml, json: 123)).to eql('')
      end

      it 'returns an empty string if json does not have either an :affiliation_id or a :name' do
        json = JSON.parse({ foo: 'bar' }.to_json)
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql('')
      end

      it 'strips off any text in parenthesis from the name' do
        json['name'] = 'Example College (example.com) (California)'
        json.delete('affiliation_id')
        expected = <<~XML
          <affiliation>Example College</affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the :name is not provided' do
        json['affiliation_id']['type'] = 'foo'
        json.delete('name')
        expected = <<~XML
          <affiliation>https://ror.org/1234567890</affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the :affiliation_id is not provided' do
        json.delete('affiliation_id')
        expected = <<~XML
          <affiliation>Example University</affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the identifier type is not a known SCHEME' do
        json['affiliation_id']['type'] = 'foo'
        expected = <<~XML
          <affiliation>Example University</affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the identifier type is a known SCHEME' do
        expected = <<~XML
          <affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
            Example University
          </affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json)).to eql(expected)
      end

      it 'adheres to specified :tab_count' do
        tabs = described_class::TAB * 2
        expected = <<~XML
          #{tabs}<affiliation affiliationIdentifier="https://ror.org/1234567890" affiliationIdentifierScheme="ROR">
          #{tabs}#{described_class::TAB}Example University
          #{tabs}</affiliation>
        XML
        expect(described_class.send(:affiliation_to_xml, json: json, tab_count: 2)).to eql(expected)
      end
    end

    describe 'identifier_to_xml(json:, type:, tab_count:)' do
      it 'returns an empty string if json is not a Hash' do
        expect(described_class.send(:identifier_to_xml, json: 123)).to eql('')
      end

      it 'returns the expected XML when the identifier type could not be determined' do
        json = JSON.parse({ identifier: 'bar', type: 'other' }.to_json)
        expected = <<~XML
          <fooIdentifier>bar</fooIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json, type: 'foo')).to eql(expected)
      end

      it 'defaults tp <nameIdentifier> if no :type is specified' do
        json = JSON.parse({ identifier: 'bar' }.to_json)
        expected = <<~XML
          <nameIdentifier>bar</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)

        json = JSON.parse({ identifier: 'http://foo.bar/articles/12345', type: 'ror' }.to_json)
        expected = <<~XML
          <nameIdentifier schemeURI="#{described_class::SCHEMES[:ror]}" nameIdentifierScheme="ROR">
          #{described_class::TAB}http://foo.bar/articles/12345
          </nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'appends "http://" to the URL is necessary' do
        json = JSON.parse({ type: 'foo', identifier: 'foo.bar/articles/12345' }.to_json)
        expected = <<~XML
          <nameIdentifier>http://foo.bar/articles/12345</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the identifier is a URL' do
        json = JSON.parse({ type: 'foo', identifier: 'https://foo.bar/articles/12345' }.to_json)
        expected = <<~XML
          <nameIdentifier>https://foo.bar/articles/12345</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML for a known SCHEME' do
        json = JSON.parse({ identifier: 'http://foo.bar/articles/12345', type: 'isni' }.to_json)
        expected = <<~XML
          <nameIdentifier schemeURI="#{described_class::SCHEMES[:isni]}" nameIdentifierScheme="ISNI">
          #{described_class::TAB}http://foo.bar/articles/12345
          </nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'appends the DOI_URL to the DOI is necessary' do
        json = JSON.parse({ type: 'foo', identifier: '99.53423/articles/12345' }.to_json)
        expected = <<~XML
          <nameIdentifier>#{described_class::DOI_URL}/99.53423/articles/12345</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'returns the expected XML when the identifier is a DOI' do
        json = JSON.parse({ type: 'foo', identifier: 'https://doi.org/19.12345/articles.123/12345' }.to_json)
        expected = <<~XML
          <nameIdentifier>https://doi.org/19.12345/articles.123/12345</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json)).to eql(expected)
      end

      it 'adheres to specified :tab_count' do
        json = JSON.parse({ type: 'foo', identifier: 'https://doi.org/19.12345/articles.123/12345' }.to_json)
        tabs = described_class::TAB * 2
        expected = <<~XML
          #{tabs}<nameIdentifier>https://doi.org/19.12345/articles.123/12345</nameIdentifier>
        XML
        expect(described_class.send(:identifier_to_xml, json: json, tab_count: 2)).to eql(expected)
      end
    end

    describe 'funding_to_xml(json:, tab_count:)' do
      let!(:json) do
        {
          title: 'Example DMP',
          name: 'Example Funding Organization',
          identifier: 'http://dx.doi.org/10.13039/100005595',
          grant: 'https://nfo.example.org/awards/098765'
        }
      end

      it 'returns an empty string if json is not a Hash' do
        expect(described_class.send(:funding_to_xml, json: 123)).to eql('')
      end

      it 'returns the expected XML' do
        expected = <<~XML
          <fundingReference>
          #{described_class::TAB}<funderName>Example Funding Organization</funderName>
          #{described_class::TAB}<funderIdentifier funderIdentifierType="Crossref Funder ID">http://dx.doi.org/10.13039/100005595</funderIdentifier>
          #{described_class::TAB}<awardNumber awardURI="https://nfo.example.org/awards/098765">https://nfo.example.org/awards/098765</awardNumber>
          #{described_class::TAB}<awardTitle>Example DMP</awardTitle>
          </fundingReference>
        XML
        expect(described_class.send(:funding_to_xml, json: json)).to eql(expected)
      end

      it 'skips the <funderIdentifier> if no :funder_id was specified' do
        json.delete(:identifier)
        expected = <<~XML
          <fundingReference>
          #{described_class::TAB}<funderName>Example Funding Organization</funderName>
          #{described_class::TAB}<awardNumber awardURI="https://nfo.example.org/awards/098765">https://nfo.example.org/awards/098765</awardNumber>
          #{described_class::TAB}<awardTitle>Example DMP</awardTitle>
          </fundingReference>
        XML
        expect(described_class.send(:funding_to_xml, json: json)).to eql(expected)
      end

      it 'skips the <awardNumber> and <awardTitle> if no :grant_id was specified' do
        json.delete(:grant)
        expected = <<~XML
          <fundingReference>
          #{described_class::TAB}<funderName>Example Funding Organization</funderName>
          #{described_class::TAB}<funderIdentifier funderIdentifierType="Crossref Funder ID">http://dx.doi.org/10.13039/100005595</funderIdentifier>
          </fundingReference>
        XML
        expect(described_class.send(:funding_to_xml, json: json)).to eql(expected)
      end

      it 'adheres to specified :tab_count' do
        tabs = described_class::TAB * 2
        expected = <<~XML
          #{tabs}<fundingReference>
          #{tabs}#{described_class::TAB}<funderName>Example Funding Organization</funderName>
          #{tabs}#{described_class::TAB}<funderIdentifier funderIdentifierType="Crossref Funder ID">http://dx.doi.org/10.13039/100005595</funderIdentifier>
          #{tabs}#{described_class::TAB}<awardNumber awardURI="https://nfo.example.org/awards/098765">https://nfo.example.org/awards/098765</awardNumber>
          #{tabs}#{described_class::TAB}<awardTitle>Example DMP</awardTitle>
          #{tabs}</fundingReference>
        XML
        expect(described_class.send(:funding_to_xml, json: json, tab_count: 2)).to eql(expected)
      end
    end

    describe 'related_id_to_xml(json:, tab_count:)' do
      let!(:json) do
        JSON.parse({
          descriptor: 'is_metadata_for',
          work_type: 'dmp',
          type: 'url',
          identifier: "#{mock_url}/dmps/#{dmp_id}.pdf"
        }.to_json)
      end

      it 'returns an empty string if json is not a Hash' do
        expect(described_class.send(:related_id_to_xml, json: 123)).to eql('')
      end

      it 'returns the expected XML' do
        expected = <<~XML
          <relatedIdentifier relationType="IsMetadataFor" relatedIdentifierType="DOI">
          #{described_class::TAB}#{mock_url}/dmps/#{dmp_id}.pdf
          </relatedIdentifier>
        XML
        expect(described_class.send(:related_id_to_xml, json: json)).to eql(expected)
      end

      it 'uses a :descriptor of "References" if none was specified' do
        json.delete('descriptor')
        expected = <<~XML
          <relatedIdentifier relationType="References" relatedIdentifierType="DOI">
          #{described_class::TAB}#{mock_url}/dmps/#{dmp_id}.pdf
          </relatedIdentifier>
        XML
        expect(described_class.send(:related_id_to_xml, json: json)).to eql(expected)
      end

      it 'adheres to specified :tab_count' do
        tabs = described_class::TAB * 2
        expected = <<~XML
          #{tabs}<relatedIdentifier relationType="IsMetadataFor" relatedIdentifierType="DOI">
          #{tabs}#{described_class::TAB}#{mock_url}/dmps/#{dmp_id}.pdf
          #{tabs}</relatedIdentifier>
        XML
        expect(described_class.send(:related_id_to_xml, json: json, tab_count: 2)).to eql(expected)
      end
    end

    describe 'identifier_type(json:)' do
      it 'returns URL if the :json is not a Hash' do
        expect(described_class.send(:identifier_type, json: '{"foo":"bar"}')).to eql('URL')
      end

      it 'returns the schema if it exists in the SCHEMES list' do
        json = JSON.parse({ type: 'ror', identifier: '12345' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('ROR')
        json = JSON.parse({ type: 'orcid', identifier: '12345' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('ORCID')
        json = JSON.parse({ type: 'isni', identifier: '12345' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('ISNI')
        json = JSON.parse({ type: 'grid', identifier: '12345' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('GRID')
      end

      it 'returns DOI if the :identifier is a valid DOI' do
        json = JSON.parse({ identifier: dmp_id }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('DOI')
        json = JSON.parse({ identifier: "doi.org/#{dmp_id}" }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('DOI')
        json = JSON.parse({ type: 'doi', identifier: "doi.org/#{dmp_id}" }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('DOI')
        json = JSON.parse({ type: 'url', identifier: "http://doi.org/#{dmp_id}" }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('DOI')
        json = JSON.parse({ type: 'doi', identifier: "http://doi.org/#{dmp_id}" }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('DOI')
      end

      it 'returns nil if the type could not be determined' do
        json = JSON.parse({ identifier: 'ABCDEFG' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to be_nil
        json = JSON.parse({ identifier: 123_345 }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to be_nil
      end

      it 'returns URL if the :identifier is a URL format and is not a DOI or in the SCHEMES list' do
        json = JSON.parse({ identifier: 'example.com/ids/356757' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('URL')
        json = JSON.parse({ identifier: 'http://example.com/34t23t' }.to_json)
        expect(described_class.send(:identifier_type, json: json)).to eql('URL')
      end
    end

    describe 'contributor_role(value:)' do
      it 'returns the DEFAULT_CONTRIBUTOR_ROLE if no :value is specified' do
        code = described_class.send(:contributor_role, value: nil)
        expect(code).to eql(described_class::DEFAULT_CONTRIBUTOR_ROLE)
      end

      it 'returns the DEFAULT_CONTRIBUTOR_ROLE if :value has no match' do
        code = described_class.send(:contributor_role, value: 123)
        expect(code).to eql(described_class::DEFAULT_CONTRIBUTOR_ROLE)
        code = described_class.send(:contributor_role, value: '')
        expect(code).to eql(described_class::DEFAULT_CONTRIBUTOR_ROLE)
        code = described_class.send(:contributor_role, value: 'foo')
        expect(code).to eql(described_class::DEFAULT_CONTRIBUTOR_ROLE)
      end

      # rubocop:disable RSpec/MultipleExpectations
      it 'returns the expected role' do
        url = 'http://credit.niso.org/contributor-roles/'
        expect(described_class.send(:contributor_role, value: "#{url}data-curation")).to eql('DataCurator')
        expect(described_class.send(:contributor_role, value: "#{url}formal-analysis")).to eql('Researcher')
        expect(described_class.send(:contributor_role, value: "#{url}software")).to eql('Researcher')
        expect(described_class.send(:contributor_role, value: "#{url}validation")).to eql('Researcher')
        expect(described_class.send(:contributor_role, value: "#{url}investigation")).to eql('ProjectLeader')
        expect(described_class.send(:contributor_role, value: "#{url}methodology")).to eql('DataManager')
        expect(described_class.send(:contributor_role, value: "#{url}project-administration")).to eql('ProjectManager')
        expect(described_class.send(:contributor_role, value: "#{url}supervision")).to eql('Supervisor')
        expect(described_class.send(:contributor_role, value: "#{url}writing-review-editing")).to eql('Editor')
      end
    end
    # rubocop:enable RSpec/MultipleExpectations

    describe 'two_char_language(val:)' do
      it 'returns the DEFAULT_LANGUAGE if no :val is specified' do
        code = described_class.send(:two_char_language, val: nil)
        expect(code).to eql(described_class::DEFAULT_LANGUAGE)
      end

      it 'returns the DEFAULT_LANGUAGE if no :val has no match' do
        code = described_class.send(:two_char_language, val: 'zzzz')
        expect(code).to eql(described_class::DEFAULT_LANGUAGE)
        code = described_class.send(:two_char_language, val: '123')
        expect(code).to eql(described_class::DEFAULT_LANGUAGE)
        code = described_class.send(:two_char_language, val: 'zz')
        expect(code).to eql(described_class::DEFAULT_LANGUAGE)
        code = described_class.send(:two_char_language, val: '1')
        expect(code).to eql(described_class::DEFAULT_LANGUAGE)
      end

      it 'returns the the 2 character language code' do
        expect(described_class.send(:two_char_language, val: 'eng')).to eql('en')
        expect(described_class.send(:two_char_language, val: 'por')).to eql('pt')
        expect(described_class.send(:two_char_language, val: 'spa')).to eql('es')
      end
    end
  end
end
