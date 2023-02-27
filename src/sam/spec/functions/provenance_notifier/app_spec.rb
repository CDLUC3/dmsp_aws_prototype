# frozen_string_literal: true

require 'spec_helper'

# NOTE!!!!!
# ------------------------------------------------------------------------------
# If you need to use :puts style debug in the code, you should comment out the
# following line in the :before section:
#     allow(described_class).to receive(:puts).and_return(true)

RSpec.describe 'ProvenanceNotifier' do
  let!(:dmp_id) { mock_dmp_id }
  let!(:dmp) do
    json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))['dmp']
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse(prov.to_json), p_key: p_key, json: json)
  end
  let!(:event) { aws_event_bridge_event }
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:described_class) { Functions::ProvenanceNotifier }

  before do
    mock_dynamodb(item_array: [dmp])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return(mock_url)
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:log_message).and_return(true)
    allow(Responder).to receive(:respond)
    resp = { status: 200, items: [prov] }
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_pk).and_return(resp)
    allow(described_class).to receive(:puts).and_return(true)
  end

  it 'returns a 200 when the :dmphub_updater_is_provenance is true' do
    event['detail']['dmphub_updater_is_provenance'] = true
    resp = described_class.process(event: event, context: aws_context)
    err = Functions::ProvenanceNotifier::NO_NOTIFICATION
    pp resp
    expect(Responder).to have_received(:respond).with(status: 200, errors: err, event: event)
  end

  it 'returns a 400 if the :dmphub_provenance_id was not specified' do
    event['detail']['dmphub_updater_is_provenance'] = false
    event['detail'].delete('dmphub_provenance_id')
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
  end

  it 'returns a 400 if the :PK was not specified' do
    event['detail']['dmphub_updater_is_provenance'] = false
    event['detail'].delete('PK')
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_INVALID_ARGS, event: event)
  end

  # rubocop:disable RSpec/RepeatedExample
  xit 'returns a 200 if the provenance did not have a :redirectUri defined' do
    event['detail']['dmphub_updater_is_provenance'] = false
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, errors: Messages::MSG_SUCCESS, event: event)
  end
  # rubocop:enable RSpec/RepeatedExample

  xit 'returns a 403 (and contacts an admin) if we could not get an access token using the :tokenUri' do
    event['detail']['dmphub_updater_is_provenance'] = false
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 403, errors: Messages::MSG_FORBIDDEN, event: event)
  end

  xit 'returns the status code (and contacts an admin) the provenance returned if it was not a 200' do
    event['detail']['dmphub_updater_is_provenance'] = false
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'foo', event: event)
  end

  it 'returns a 500 if the event JSON was unparseable' do
    allow(described_class).to receive(:load_dmp).and_raise(JSON::ParserError)
    described_class.process(event: event, context: aws_context)
    expected = { status: 500, errors: Messages::MSG_INVALID_JSON, event: event }
    expect(Responder).to have_received(:respond).with(expected)
  end

  it 'returns a 500 if an AWS Service threw an error' do
    allow(described_class).to receive(:load_dmp).and_raise(aws_error)
    described_class.process(event: event, context: aws_context)
    expected = { status: 500, errors: Messages::MSG_SERVER_ERROR, event: event }
    expect(Responder).to have_received(:respond).with(expected)
  end

  it 'returns a 500 if a StandardError occurs' do
    allow(described_class).to receive(:load_dmp).and_raise(StandardError)
    result = described_class.process(event: event, context: aws_context)

    pp result

    expect(result[:statusCode]).to be(500)
    expect(JSON.parse(result[:body])['errors']).to eql([Messages::MSG_SERVER_ERROR])
  end

  # rubocop:disable RSpec/RepeatedExample
  it 'returns a 200 if the provenance was successfully notified' do
    event['detail']['dmphub_updater_is_provenance'] = false
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, errors: Messages::MSG_SUCCESS, event: event)
  end
  # rubocop:enable RSpec/RepeatedExample

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
  end
end
