# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpApiCore::SsmReader' do
  let!(:described_class) { Uc3DmpApiCore::SsmReader }

  let!(:ssm_client) { mock_ssm(value: 'foo', success: true) }

  before do
    allow(Uc3DmpApiCore::LogWriter).to receive(:log_error).and_return(true)
  end

  describe 'get_ssm_value(key:)' do
    let!(:test_key) { :s3_bucket_url }

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
      name = format(described_class.send(:_ssm_keys)[test_key], env: 'test')
      described_class.get_ssm_value(key: test_key)
      expect(ssm_client).to have_received(:get_parameter).with(name: name, with_decryption: true)
    end

    it 'returns nil if the SSM does not have a matching parameter' do
      allow(ENV).to receive(:fetch).and_return('test')
      mock_ssm(value: nil, success: false)
      expect(described_class.get_ssm_value(key: test_key)).to be_nil
    end

    it 'returns nil and logs an error if AWS throws an error' do
      allow(ENV).to receive(:fetch).and_return('test')
      mock_ssm(value: 'foo', success: false)
      expect(described_class.get_ssm_value(key: test_key)).to be_nil
      expect(Uc3DmpApiCore::LogWriter).to have_received(:log_error).once
    end

    it 'returns the value for the parameter from SSM' do
      name = 'foo'
      mock_ssm(value: name, success: true)
      expect(described_class.get_ssm_value(key: test_key)).to eql(name)
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
