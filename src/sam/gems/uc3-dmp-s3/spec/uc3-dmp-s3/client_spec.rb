# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpS3::Client' do
  let!(:described_class) { Uc3DmpS3::Client }
  let!(:client_err) { Uc3DmpS3::ClientError }

  before do
    ENV['S3_BUCKET'] = 's3://foo'
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'put_narrative(document:, dmp_id: nil, base64: false)' do
    it 'returns nil if :document is not a String' do
      expect(described_class.put_narrative(document: nil)).to be_nil
    end

    it 'returns nil if :document is an empty String' do
      expect(described_class.put_narrative(document: '')).to be_nil
    end

    it 'returns nil if the S3_BUCKET ENV variable is nil' do
      ENV.delete('S3_BUCKET')
      expect(described_class.put_narrative(document: 'foo file')).to be_nil
    end

    it 'decodes base64 if necessary' do
      allow(Base64).to receive(:decode64)
      allow(described_class).to receive(:_put_object).and_return('foo')
      described_class.put_narrative(document: 'foo file', base64: true)
      expect(Base64).to have_received(:decode64).once
    end

    it 'appends the key prefix' do
      allow(described_class).to receive(:_put_object).and_return('foo')
      expect(described_class.put_narrative(document: 'foo file', dmp_id: 'foo/bar')).to eql('foo')
    end

    # rubocop:disable RSpec/ExampleLength
    it 'uses the appropriate tags if a DMP ID was specified' do
      allow(CGI).to receive(:escape)
      allow(Time).to receive(:now)
      allow(described_class).to receive(:_put_object).and_return('foo')
      described_class.put_narrative(document: 'foo file', dmp_id: 'foo/bar')
      expect(CGI).to have_received(:escape).once
      expect(Time).not_to have_received(:now)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it 'uses the appropriate tags if no DMP ID was specified' do
      now = Time.now
      allow(CGI).to receive(:escape)
      allow(Time).to receive(:now).and_return(now)
      allow(described_class).to receive(:_put_object).and_return('foo')
      described_class.put_narrative(document: 'foo file')
      expect(Time).to have_received(:now).once
      expect(CGI).not_to have_received(:escape)
    end
    # rubocop:enable RSpec/ExampleLength

    it 'handles AWS ServiceErrors properly' do
      allow(described_class).to receive(:_put_object).and_raise(aws_error)
      expect { described_class.put_narrative(document: 'foo file') }.to raise_error(client_err)
    end
  end

  describe 'get_narrative(key:)' do
    it 'returns nil if :key is not a String' do
      expect(described_class.get_narrative(key: nil)).to be_nil
    end

    it 'returns nil if :key is an empty String' do
      expect(described_class.get_narrative(key: '')).to be_nil
    end

    it 'returns nil if the S3_BUCKET ENV variable is nil' do
      ENV.delete('S3_BUCKET')
      expect(described_class.get_narrative(key: 'foo')).to be_nil
    end

    it 'returns nil if the :key could not be found' do
      allow(described_class).to receive(:_get_object).and_return(nil)
      expect(described_class.get_narrative(key: 'foo')).to be_nil
    end

    it 'appends the key prefix if necessary' do
      expected = { key: "#{described_class::NARRATIVE_KEY_PREFIX}foo" }
      allow(described_class).to receive(:_get_object).and_return('foo file')
      expect(described_class.get_narrative(key: 'foo')).to eql('foo file')
      expect(described_class).to have_received(:_get_object).with(expected)
    end

    it 'does not append the key prefix if :key starts with the prefix already' do
      key = "#{described_class::NARRATIVE_KEY_PREFIX}foo"
      allow(described_class).to receive(:_get_object).and_return('foo file')
      expect(described_class.get_narrative(key:)).to eql('foo file')
      expect(described_class).to have_received(:_get_object).with(key:)
    end

    it 'returns the object' do
      allow(described_class).to receive(:_get_object).and_return('bar')
      expect(described_class.get_narrative(key: 'foo')).to eql('bar')
    end

    it 'handles AWS ServiceErrors properly' do
      allow(described_class).to receive(:_get_object).and_raise(aws_error)
      expect { described_class.get_narrative(key: 'foo') }.to raise_error(client_err)
    end
  end

  describe '_put_object(key:, payload:, tags:)' do
    it 'returns nil if :key is not a String' do
      mock_s3_writer
      expect(described_class.send(:_put_object, key: nil, payload: 'foo file')).to be_nil
    end

    it 'returns nil if :key is an empty String' do
      mock_s3_writer
      expect(described_class.send(:_put_object, key: '', payload: 'foo file')).to be_nil
    end

    it 'returns nil if :payload is nil' do
      mock_s3_writer
      expect(described_class.send(:_put_object, key: 'foo', payload: nil)).to be_nil
    end

    it 'returns nil if the S3_BUCKET ENV variable is nil' do
      ENV.delete('S3_BUCKET')
      mock_s3_writer
      expect(described_class.send(:_put_object, key: 'foo', payload: 'foo file')).to be_nil
    end

    it 'returns nil if the operation was not successful' do
      mock_s3_writer(success: false)
      expect(described_class.send(:_put_object, key: 'foo', payload: 'foo file')).to be_nil
    end

    it 'returns the object key if successful' do
      mock_s3_writer
      expect(described_class.send(:_put_object, key: 'foo', payload: 'foo file')).to eql('foo')
    end
  end

  describe '_get_object(key:)' do
    it 'returns nil if :key is not a String' do
      mock_s3_reader
      expect(described_class.send(:_get_object, key: nil)).to be_nil
    end

    it 'returns nil if :key is an empty String' do
      mock_s3_reader
      expect(described_class.send(:_get_object, key: '')).to be_nil
    end

    it 'returns nil if the S3_BUCKET ENV variable is nil' do
      ENV.delete('S3_BUCKET')
      mock_s3_reader
      expect(described_class.send(:_get_object, key: 'foo')).to be_nil
    end

    it 'returns nil if the :key could not be found' do
      mock_s3_reader(success: false)
      expect(described_class.send(:_get_object, key: 'foo')).to be_nil
    end

    it 'returns the object if it is a String' do
      allow(described_class).to receive(:_get_object).and_return('bar')
      expect(described_class.get_narrative(key: 'foo')).to eql('bar')
    end

    it 'returns the object if it is an IO' do
      mock_s3_reader(success: true)
      expect(described_class.send(:_get_object, key: 'foo')).to eql('io body')
    end

    it 'returns the narrative PDF' do
      mock_s3_reader(success: true, as_string: true)
      expect(described_class.send(:_get_object, key: 'foo')).to eql('string body')
    end
  end
end
