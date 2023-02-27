# frozen_string_literal: true

require 'spec_helper'

# NOTE!!!!!
# ------------------------------------------------------------------------------
# If you need to use :puts style debug in the code, you should comment out the
# following line in the :before section:
#     allow(described_class).to receive(:puts).and_return(true)

RSpec.describe 'GetDmps' do
  let!(:prov) { { PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}foo" } }
  let!(:dmps) do
    dmp_id = mock_dmp_id
    json = mock_dmp_item
    p_key = KeyHelper.append_pk_prefix(dmp: dmp_id)
    [DmpHelper.annotate_dmp(provenance: JSON.parse({ PK: 'foo ' }.to_json), p_key: p_key, json: json)]
  end
  let!(:event) { aws_event(args: { queryStringParameters: { page: 1, per_page: 1 } }) }
  let!(:described_class) { Functions::GetDmps }

  before do
    # Mock all of the calls to AWS resoures and Lambda Layer functions
    mock_dynamodb(item_array: [])
    mock_ssm(value: 'foo')
    allow(KeyHelper).to receive(:dmp_id_base_url).and_return('http://example.com/dmps')
    allow(SsmReader).to receive(:debug_mode?).and_return(false)
    allow(Responder).to receive(:log_error).and_return(true)
    allow(Responder).to receive(:respond)
    resp = { status: 200, items: [prov] }
    allow_any_instance_of(ProvenanceFinder).to receive(:provenance_from_lambda_cotext).and_return(resp)
    allow(described_class).to receive(:puts).and_return(true)
  end

  it 'returns any errors returned by the Lambda Layer' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_return({ status: 499, error: 'foo',
                                                                           items: [] })
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 499, errors: 'foo', event: event).once
  end

  it 'returns a 200 and the DMPs' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_return({ status: 200, items: dmps })
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:respond).with(status: 200, items: dmps, event: event).once
  end

  it 'returns a 500 when there is a server error' do
    allow_any_instance_of(DmpFinder).to receive(:search_dmps).and_raise(aws_error)
    described_class.process(event: event, context: aws_context)
    expect(Responder).to have_received(:log_error).once
  end
end
