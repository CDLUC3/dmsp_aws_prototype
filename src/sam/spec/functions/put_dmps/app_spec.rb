# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PutDmp' do
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmp_id) { mock_dmp_id }
  let!(:original) do
    json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)
  end
  let!(:changes) do
    changes = DmpHelper.deep_copy_dmp(obj: original)
    changes['dmp']['title'] = 'Changed from foo to bar.'
    changes['dmp']['modified'] = '2022-09-21T15:29:32+1'
    changes
  end
  let!(:event) { aws_event(args: { pathParameters: { dmp_id: dmp_id }, body: changes }) }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_dynamodb(item_array: [])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return('http://doi.org/')
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    resp = JSON.parse({ status: 200, items: prov }.to_json)
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_lambda_cotext).and_return(resp)
  end

  it 'returns a 400 when the :body is nil' do
    Functions::PutDmp.process(event: aws_event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: aws_event,
                                                      errors: Messages::MSG_DMP_INVALID_DMP_ID).once
  end

  it 'returns a 400 when the DMP ID is not a valid DOI' do
    allow(KeyHelper).to receive(:format_dmp_id).and_return(nil)
    allow(KeyHelper).to receive(:append_pk_prefix).and_return(nil)
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event,
                                                      errors: Messages::MSG_DMP_INVALID_DMP_ID).once
  end

  it 'returns a 400 when the :body is an empty string' do
    event = aws_event(args: { body: '' })
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event,
                                                      errors: Messages::MSG_DMP_INVALID_DMP_ID).once
  end

  it 'returns a 400 when the :body is not validated by the JSON schema' do
    allow(Validator).to receive(:validate).and_return({ valid: false, errors: ['foo'] })
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: ['foo'], event: event).once
  end

  it 'returns the errors returned when trying to create the DMP record' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 499, error: 'bar' })
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'bar', event: event).once
  end

  it 'returns a 200 when the DMP was sucessfully created' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    allow_any_instance_of(DmpFinder).to receive(:find_dmp_by_pk).and_return({ status: 200, items: [original] })
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    expected = DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: changes)
    allow_any_instance_of(DmpUpdater).to receive(:update_dmp).and_return({ status: 200, items: [expected] })
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, items: [expected],
                                                      errors: nil, event: event).once
  end

  it 'returns a 500 when there is a server error' do
    allow(Validator).to receive(:validate).and_raise(aws_error)
    Functions::PutDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
