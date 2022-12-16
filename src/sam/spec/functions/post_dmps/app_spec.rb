# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'PostDmps' do
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmp_id) { mock_dmp_id }
  let!(:dmp) { JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/minimal.json")) }
  let!(:event) { aws_event(args: { body: dmp['author'] }) }

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

  it 'returns a 400 when the :body is nil' do
    Functions::PostDmps.process(event: aws_event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: [Messages::MSG_EMPTY_JSON],
                                                      event: aws_event).once
  end

  it 'returns a 400 when the :body is an empty string' do
    event = aws_event(args: { body: '' })
    Functions::PostDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: [Messages::MSG_EMPTY_JSON],
                                                      event: event).once
  end

  it 'returns a 400 when the :body is not validated by the JSON schema' do
    allow(Validator).to receive(:validate).and_return({ valid: false, errors: ['foo'] })
    Functions::PostDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, errors: ['foo'], event: event).once
  end

  it 'returns the errors returned when trying to create the DMP record' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    allow_any_instance_of(DmpCreator).to receive(:create_dmp).and_return({ status: 499, error: 'bar' })
    Functions::PostDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'bar', event: event).once
  end

  it 'returns a 201 when the DMP was sucessfully created' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    dmp = DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)
    allow_any_instance_of(DmpCreator).to receive(:create_dmp).and_return({ status: 201, items: [dmp] })
    Functions::PostDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 201, items: [dmp], event: event).once
  end

  it 'returns a 500 when there is a server error' do
    allow(Validator).to receive(:validate).and_raise(aws_error)
    Functions::PostDmps.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
