# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ValidateDmp' do
  let!(:dmp) do
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: mock_dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)
  end
  let!(:event) { aws_event(args: { body: dmp }) }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
  end

  it 'returns a 400 when the :body is nil' do
    Functions::ValidateDmp.process(event: aws_event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: aws_event,
                                                      errors: [Messages::MSG_EMPTY_JSON]).once
  end

  it 'returns a 400 when the :body is an empty string' do
    event = aws_event(args: { body: '' })
    Functions::ValidateDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event,
                                                      errors: [Messages::MSG_EMPTY_JSON]).once
  end

  it 'returns a 400 when the :body is not validated by the JSON schema' do
    allow(Validator).to receive(:validate).and_return({ valid: false, errors: ['foo'] })
    Functions::ValidateDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event, errors: ['foo']).once
  end

  it 'returns a 200 when the DMP JSON is valid' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    Functions::ValidateDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, event: event,
                                                      items: [Messages::MSG_VALID_JSON]).once
  end

  it 'returns a 500 when there is a server error' do
    allow(Validator).to receive(:validate).and_raise(aws_error)
    Functions::ValidateDmp.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
