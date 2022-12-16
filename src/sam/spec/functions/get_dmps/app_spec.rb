# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'GetDmps' do
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmps) do
    dmp_id = mock_dmp_id
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    [DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)]
  end
  let!(:event) { aws_event(args: { queryStringParameters: { page: 1, per_page: 1 } }) }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_dynamodb(item_array: [])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return('http://example.com/dmps')
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    resp = JSON.parse({ status: 200, items: prov }.to_json)
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_lambda_cotext).and_return(resp)
  end

  it 'returns any errors returned by the Lambda Layer' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_return({ status: 499, error: 'foo',
                                                                           items: [] })
    Functions::GetDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'foo', event: event).once
  end

  it 'returns a 200 and the DMPs' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_return({ status: 200, items: dmps })
    Functions::GetDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, items: dmps, event: event).once
  end

  it 'returns a 500 when there is a server error' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_raise(aws_error)
    Functions::GetDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
