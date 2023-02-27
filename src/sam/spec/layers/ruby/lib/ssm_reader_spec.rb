# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SsmReader' do
  let!(:described_class) { SsmReader }

  let!(:ssm_client) { mock_ssm(value: 'foo', success: true) }

  before do
    allow(Responder).to receive(:log_error).and_return(true)
  end

  describe 'get_ssm_value(key:)' do
    # Note that tests verify that we are actually pulling from SSM occur in the API tests
    # which have access to the AWS resources
    it 'returns nil if the :key is not a String' do
      expect(described_class.get_ssm_value(key: nil)).to be_nil
    end

    it 'returns nil if the :key is an empty String' do
      expect(described_class.get_ssm_value(key: '  ')).to be_nil
    end

    it 'looks for the environment version of the :key' do
      allow(ENV).to receive(:fetch).and_return('test')
      name = format(described_class::S3_BUCKET_URL, env: 'test')
      described_class.get_ssm_value(key: described_class::S3_BUCKET_URL)
      expect(ssm_client).to have_received(:get_parameter).with(name: name, with_decryption: true)
    end

    it 'returns nil if the SSM does not have a matching parameter' do
      allow(ENV).to receive(:fetch).and_return('test')
      mock_ssm(value: nil, success: false)
      expect(described_class.get_ssm_value(key: described_class::S3_BUCKET_URL)).to be_nil
    end

    it 'returns nil and logs an error if AWS throws an error' do
      allow(ENV).to receive(:fetch).and_return('test')
      mock_ssm(value: 'foo', success: false)
      expect(described_class.get_ssm_value(key: described_class::S3_BUCKET_URL)).to be_nil
      expect(Responder).to have_received(:log_error).once
    end

    it 'returns the value for the parameter from SSM' do
      name = 'foo'
      mock_ssm(value: name, success: true)
      allow(ENV).to receive(:fetch).and_return('test')
      expect(described_class.get_ssm_value(key: 'foo/bar')).to eql(name)
    end
  end

  describe 'debug_mode?' do
    it 'returns true if the SSM parameter is set to true' do
      allow(described_class).to receive(:get_ssm_value).and_return('true')
      expect(described_class.debug_mode?).to be(true)
      allow(described_class).to receive(:get_ssm_value).and_return('True')
      expect(described_class.debug_mode?).to be(true)
      allow(described_class).to receive(:get_ssm_value).and_return('true ')
      expect(described_class.debug_mode?).to be(true)
    end

    it 'returns false if the SSM parameter is NOT set to true' do
      allow(described_class).to receive(:get_ssm_value).and_return('false')
      expect(described_class.debug_mode?).to be(false)
      allow(described_class).to receive(:get_ssm_value).and_return('False')
      expect(described_class.debug_mode?).to be(false)
      allow(described_class).to receive(:get_ssm_value).and_return('0')
      expect(described_class.debug_mode?).to be(false)
      allow(described_class).to receive(:get_ssm_value).and_return('Foo')
      expect(described_class.debug_mode?).to be(false)
    end
  end
end
