# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpApiCore::Notifier' do
  let!(:described_class) { Uc3DmpApiCore::Notifier }

  before do
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'notify_administrator(source:, details:, event:)' do
    let!(:source) { 'Example class.method' }
    let!(:details) { { detail1: 'foo-detail1', detail2: 'foo-detail2' } }
    let!(:event) { { event1: 'foo-event1', event2: 'foo-event2' } }

    it 'returns true when successful' do
      sns_client = mock_sns
      allow(sns_client).to receive(:publish).and_return('Message sent:')
      expect(described_class.notify_administrator(source:, details:, event:)).to be(true)
    end

    it 'handles AWS errors by logging directly to stdout and returns false' do
      mock_sns(success: false)
      expect(described_class.notify_administrator(source:, details:)).to be(false)
      expect(described_class).to have_received(:puts).twice
    end
  end
end
