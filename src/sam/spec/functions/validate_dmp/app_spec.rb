# frozen_string_literal: true

require 'spec_helper'

# NOTE!!!!!
# ------------------------------------------------------------------------------
# If you need to use :puts style debug in the code, you should comment out the
# following line in the :before section:
#     allow(described_class).to receive(:puts).and_return(true)

RSpec.describe 'ValidateDmp' do
  let!(:described_class) { Functions::ValidateDmp }
  let!(:dmp) do
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: mock_dmp_id)
    DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)
  end
  let!(:event) { aws_event(args: { body: dmp }) }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_ssm(value: 'foo')
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    allow(described_class).to receive(:puts).and_return(true)
  end

  it 'returns a 400 when the :body is nil' do
    described_class.process(event: aws_event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: aws_event,
                                                      errors: [Messages::MSG_EMPTY_JSON]).once
  end

  it 'returns a 400 when the :body is an empty string' do
    event = aws_event(args: { body: '' })
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event,
                                                      errors: [Messages::MSG_EMPTY_JSON]).once
  end

  it 'returns a 400 when the :body is not validated by the JSON schema' do
    allow(Validator).to receive(:validate).and_return({ valid: false, errors: ['foo'] })
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 400, event: event, errors: ['foo']).once
  end

  it 'returns a 200 when the DMP JSON is valid' do
    allow(Validator).to receive(:validate).and_return({ valid: true })
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, event: event,
                                                      items: [Messages::MSG_VALID_JSON]).once
  end

  it 'returns a 500 when there is a server error' do
    allow(Validator).to receive(:validate).and_raise(aws_error)
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
