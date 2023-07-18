# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpApiCore::LogWriter' do
  let!(:described_class) { Uc3DmpApiCore::LogWriter }

  before do
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'log_error(source:, message:, details: {}, event: {})' do
    # Note that tests that verify that the errors actually end up in CloudWatch occur in the
    # API tests which have access to the AWS resources
    it 'returns false is :source is nil' do
      expect(described_class.log_error(source: nil, message: 'Lorem ipsum')).to be(false)
    end

    it 'returns false is :message is nil' do
      expect(described_class.log_error(source: 'api/foos', message: nil)).to be(false)
    end

    it 'returns false if Notifier.notify_administrator fails' do
      allow(Uc3DmpApiCore::Notifier).to receive(:notify_administrator).and_return(false)
      expect(described_class.log_error(source: 'api/foo', message: 'Lorem ipsum')).to be(false)
    end

    it 'returns true if Notifier.notify_administrator succeeds' do
      allow(Uc3DmpApiCore::Notifier).to receive(:notify_administrator).and_return(true)
      allow(described_class).to receive(:_notify_administrator).and_return('foo')
      expect(described_class.log_error(source: 'api/foo', message: 'Lorem ipsum')).to be(true)
    end
  end

  describe 'log_message(source:, message:, details: {})' do
    it 'returns false is :source is nil' do
      expect(described_class.log_message(source: nil, message: 'Lorem ipsum')).to be(false)
    end

    it 'returns false is :message is nil' do
      expect(described_class.log_message(source: 'api/foos', message: nil)).to be(false)
    end

    it 'succeeds' do
      expect(described_class.log_message(source: 'api/foo', message: 'Lorem ipsum')).to be(true)
    end
  end
end
