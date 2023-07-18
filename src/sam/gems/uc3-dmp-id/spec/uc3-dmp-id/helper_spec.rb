# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpId::Helper' do
  let!(:described_class) { Uc3DmpId::Helper }

  before do
    mock_uc3_dmp_dynamo
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'append_pk_prefix(p_key:)' do
    it 'appends the prefix' do
      key = 'foo/bar'
      expect(described_class.append_pk_prefix(p_key: key)).to eql("#{described_class::PK_DMP_PREFIX}#{key}")
    end

    it 'returns the :p_key as is if it already starts with the prefix' do
      key = "#{described_class::PK_DMP_PREFIX}foo/bar"
      expect(described_class.append_pk_prefix(p_key: key)).to eql(key)
    end
  end

  describe 'remove_pk_prefix(p_key:)' do
    it 'returns the :p_key as is if it does not start with the prefix' do
      key = 'foo/bar'
      expect(described_class.remove_pk_prefix(p_key: key)).to eql(key)
    end

    it 'removes the prefix' do
      key = "foo/bar"
      expect(described_class.remove_pk_prefix(p_key: "#{described_class::PK_DMP_PREFIX}#{key}")).to eql(key)
    end
  end
end
