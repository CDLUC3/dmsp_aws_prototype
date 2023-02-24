# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Functions::PdfDownloader' do
  let!(:dmp_id) { mock_dmp_id }
  let!(:prov) do
    JSON.parse({ PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo",
                 downloadUri: 'http://example.com/downloads/' }.to_json)
  end
  let!(:dmp) do
    json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))['dmp']
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse(prov.to_json), p_key: p_key, json: json)
  end
  let!(:event) do
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    ev = aws_sns_event
    ev['Records'].first['Sns']['Message'] = JSON.parse({ location: 'http://example.com/foo/55555.pdf',
                                                         provenance: prov['PK'], dmp: p_key }.to_json)
    ev
  end
  let!(:described_class) { Functions::PdfDownloader }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_dynamodb(item_array: [dmp])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return(mock_url)
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    resp = JSON.parse({ status: 200, items: prov }.to_json)
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_pk).and_return(resp)
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

    it 'returns a 500 error if the download fails' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      allow(described_class).to receive(:download_dmp).and_return(nil)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 500, errors: Messages::MSG_DOWNLOAD_FAILURE,
                                                        event: event)
    end

    it 'returns a 500 error if the download could not be saved to S3' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      allow(described_class).to receive(:download_dmp).and_return('Testing Foo')
      allow(described_class).to receive(:save_document).and_return(nil)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 500, errors: Messages::MSG_S3_FAILURE,
                                                        event: event)
    end

    it 'returns a 500 if the original DMP record could not be updated' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      allow(described_class).to receive(:download_dmp).and_return('Testing Foo')
      allow(described_class).to receive(:save_document).and_return('dmps/foo.pdf')
      allow(described_class).to receive(:update_document_url).and_return(false)
      result = described_class.process(event: event, context: aws_context)

      p 'RESULT'
      pp result

      expect(Responder).to have_received(:respond).with(status: 500, errors: Messages::MSG_SERVER_ERROR,
                                                        event: event)
    end

    it 'returns a 200 when successful' do
      allow(described_class).to receive(:load_dmp).and_return(dmp)
      allow(described_class).to receive(:download_dmp).and_return('Testing Foo')
      allow(described_class).to receive(:save_document).and_return('dmps/foo.pdf')
      allow(described_class).to receive(:update_document_url).and_return(true)
      described_class.process(event: event, context: aws_context)
      expect(Responder).to have_received(:respond).with(status: 200, errors: Messages::MSG_SUCCESS, event: event)
    end

    it 'returns a 500 when the :message was not parseable JSON' do
      allow(described_class).to receive(:load_dmp).and_raise(JSON::ParserError)
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
      result = described_class.process(event: event, context: aws_context)
      expect(result[:statusCode]).to be(500)
      expect(result[:body]).to eql("{\"errors\":[\"#{Messages::MSG_SERVER_ERROR}\"]}")
    end
  end

  describe 'private methods' do
    describe 'load_dmp(provenance:, dmp_pk:, table:, client:, debug:)' do
      let!(:dmp_pk) { "#{KeyHelper::PK_DMP_PREFIX}#{dmp_id}" }

      it 'returns nil if :provenance is nil' do
        result = described_class.send(:load_dmp, provenance: nil, dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :dmp_pk is nil' do
        result = described_class.send(:load_dmp, provenance: prov, dmp_pk: nil, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :table is nil' do
        result = described_class.send(:load_dmp, provenance: prov, dmp_pk: dmp_pk, table: nil, client: 123)
        expect(result).to be_nil
      end

      it 'returns nil if :client is nil' do
        result = described_class.send(:load_dmp, provenance: prov, dmp_pk: dmp_pk, table: 'foo', client: nil)
        expect(result).to be_nil
      end

      it 'returns nil if DMP could not be found' do
        allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 404 })
        result = described_class.send(:load_dmp, provenance: prov, dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to be_nil
      end

      it 'returns the DMP' do
        expected = { status: 200, items: [JSON.parse({ dmp: dmp }.to_json)] }
        allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return(expected)
        result = described_class.send(:load_dmp, provenance: prov, dmp_pk: dmp_pk, table: 'foo', client: 123)
        expect(result).to eql(dmp)
      end
    end

    describe 'download_dmp(provenance:, location:)' do
      let!(:url) { 'http://example.com/downloads/33333.pdf' }

      it 'returns nil if :provenance is nil' do
        expect(described_class.send(:download_dmp, provenance: nil, location: url)).to be_nil
      end

      it 'returns nil if :location is nil' do
        expect(described_class.send(:download_dmp, provenance: prov, location: nil)).to be_nil
      end

      it 'returns nil if the :location does not match the :provenance :downloadUri' do
        result = described_class.send(:download_dmp, provenance: prov, location: 'http://foo.bar')
        expect(result).to be_nil
      end

      it 'return nil if HTTParty does not return a 200' do
        mock_httparty(code: 400, body: 'foo')
        result = described_class.send(:download_dmp, provenance: prov, location: url)
        expect(result).to be_nil
      end

      it 'returns the document' do
        mock_httparty(code: 200, body: 'foo')
        result = described_class.send(:download_dmp, provenance: prov, location: url)
        expect(result).to eql('foo')
      end

      it 'returns nil if the location is not a valid URI' do
        allow(URI).to receive(:new).and_raise(URI::Error)
        result = described_class.send(:download_dmp, provenance: prov, location: url)
        expect(result).to be_nil
      end
    end

    describe 'save_document(document:, dmp_pk:)' do
      let!(:dmp_pk) { KeyHelper.append_pk_prefix(dmp: dmp_id) }

      it 'returns nil if :document is nil' do
        result = described_class.send(:save_document, document: nil, dmp_pk: dmp_pk)
        expect(result).to be_nil
      end

      it 'returns nil if :dmp_pk is nil' do
        result = described_class.send(:save_document, document: 'Foo testing', dmp_pk: nil)
        expect(result).to be_nil
      end

      it 'sends the :document to S3' do
        mock_s3(success: true)
        result = described_class.send(:save_document, document: 'Foo testing', dmp_pk: dmp_pk)
        expect(result.start_with?('dmps/')).to be(true)
        expect(result.end_with?('.pdf')).to be(true)
      end

      it 'returns nil if the write to S3 was not successful' do
        client = mock_s3(success: false)
        result = described_class.send(:save_document, document: 'Foo testing', dmp_pk: dmp_pk)
        expect(result).to be_nil
        expect(client).to have_received(:put_object).once
      end

      it 'handles an AWS Service Error' do
        client = mock_s3(success: false)
        allow(client).to receive(:put_object).and_raise(aws_error)
        result = described_class.send(:save_document, document: 'Foo testing.', dmp_pk: dmp_pk)
        expect(result).to be_nil
        expect(Responder).to have_received(:log_error).once
      end
    end

    describe 'update_document_url(table:, dmp:, original_uri:, object_key:, debug: false)' do
      it 'returns false if :table is nil' do
        result = described_class.send(:update_document_url, table: nil, dmp: dmp,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(false)
      end

      it 'returns false if :dmp is not a Hash' do
        result = described_class.send(:update_document_url, table: 'foo', dmp: 12_345,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(false)
      end

      it 'returns false if :original_uri is nil' do
        result = described_class.send(:update_document_url, table: 'foo', dmp: dmp,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: nil)
        expect(result).to be(false)
      end

      it 'returns false if :object_key is nil' do
        result = described_class.send(:update_document_url, table: 'foo', dmp: dmp,
                                                            object_key: nil,
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(false)
      end

      it 'returns true if the update succeeded' do
        mock_dynamodb(item_array: [dmp], success: true)
        result = described_class.send(:update_document_url, table: 'foo', dmp: dmp,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(true)
      end

      it 'returns false if update failed' do
        mock_dynamodb(item_array: [dmp], success: false)
        result = described_class.send(:update_document_url, table: 'foo', dmp: dmp,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(false)
      end

      it 'handles an AWS Service Error' do
        client = mock_dynamodb(item_array: [dmp], success: true)
        allow(client).to receive(:put_item).and_raise(aws_error)
        result = described_class.send(:update_document_url, table: 'foo', dmp: dmp,
                                                            object_key: 'dmps/123123.pdf',
                                                            original_uri: 'http://foo.bar/77777')
        expect(result).to be(false)
        expect(Responder).to have_received(:log_error).once
      end
    end

    describe 'authenticate(provenance:, debug: false)' do
      it 'returns an empty Hash if :provenance is nil' do
        expect(described_class.send(:authenticate, provenance: nil)).to eql({})
      end

      it 'returns an empty Hash if :provenance has no :tokenUri' do
        prov.delete('tokenUri')
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
      end

      it 'returns an empty Hash if :provenance has no :client_id or :client_secret' do
        prov['tokenUri'] = 'http://localhost:3000/api/v2/dmps'
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
        prov['client_id'] = '39ty247ty42yt'
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
        prov.delete('client_id')
        prov['client_secret'] = '346hy35h356h563h'
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
      end

      it 'returns an empty Hash if the :provenance system did not return an HTTP 200 status' do
        prov['tokenUri'] = 'http://localhost:3000/api/v2/dmps'
        prov['client_id'] = '39ty247ty42yt'
        prov['client_secret'] = '346hy35h356h563h'
        mock_httparty(code: 403, body: 'Unauthorized')
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
      end

      it 'returns the access token as an HTTP header' do
        prov['tokenUri'] = 'http://localhost:3000/api/v2/dmps'
        prov['client_id'] = '39ty247ty42yt'
        prov['client_secret'] = '346hy35h356h563h'
        mock_httparty(code: 200, body: '{"access_token":"12345","token_type":"Foo"}')
        result = described_class.send(:authenticate, provenance: prov)
        expect(result[:Authorization]).to eql('Foo 12345')
      end

      it 'handles a JSON parser error' do
        prov['tokenUri'] = 'http://localhost:3000/api/v2/dmps'
        prov['client_id'] = '39ty247ty42yt'
        prov['client_secret'] = '346hy35h356h563h'
        allow(HTTParty).to receive(:post).and_raise(JSON::ParserError)
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
        expect(Responder).to have_received(:log_error).once
      end

      it 'handles all other errors' do
        prov['tokenUri'] = 'http://localhost:3000/api/v2/dmps'
        prov['client_id'] = '39ty247ty42yt'
        prov['client_secret'] = '346hy35h356h563h'
        allow(HTTParty).to receive(:post).and_raise(StandardError)
        expect(described_class.send(:authenticate, provenance: prov)).to eql({})
      end
    end
  end
end
