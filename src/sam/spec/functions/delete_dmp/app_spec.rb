# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Functions::DeleteDmp' do
  let!(:dmp_id) { mock_dmp_id }
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmp) do
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo' }.to_json), p_key: p_key, json: json)
  end
  let!(:event) { aws_event(args: { pathParameters: { dmp_id: dmp_id } }) }

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
    allow(KeyHelper).to receive(:append_pk_prefix).and_return("#{KeyHelper::PK_DMP_PREFIX}##{dmp_id}")
  end

  it 'returns a 404 when the DMP ID is not provided' do
    Functions::DeleteDmp.process(event: aws_event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 404, errors: Messages::MSG_INVALID_JSON, event: aws_event)
  end

  it 'returns a 400 when the DMP ID is not a valid DOI' do
    allow(KeyHelper).to receive(:append_pk_prefix).and_return(nil)
    Functions::DeleteDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: Messages::MSG_DMP_INVALID_DMP_ID,
                                                      event: event).once
  end

  it 'returns errors from underlying lambda layer code' do
    allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 499, error: 'foo' })
    Functions::DeleteDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'foo', event: event).once
  end

  it 'returns a 200 when the DMP was sucessfully tombstoned' do
    allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [dmp] })
    allow_any_instance_of(DmpDeleter).to receive(:delete_dmp).and_return({ status: 200, items: [dmp] })
    Functions::DeleteDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, errors: nil, items: [dmp],
                                                      event: event).once
  end

  it 'returns a 500 when there is a server error' do
    allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_raise(aws_error)
    Functions::DeleteDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
