# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Uc3DmpRds::Adapter' do
  let!(:described_class) { Uc3DmpRds::Adapter }

  before do
    allow(Uc3DmpApiCore::SsmReader).to receive(:get_ssm_value).with(key: :rds_username).and_return('foo')
    allow(Uc3DmpApiCore::SsmReader).to receive(:get_ssm_value).with(key: :rds_password).and_return('bar')
    mock_active_record_base
    allow(described_class).to receive(:puts).and_return(true)
  end

  describe 'connect' do
    it 'returns true if the connection was established' do
      expect(described_class.connect).to be(true)
    end

    it 'returns false if the connection could not be established' do
      mock_active_record_base(success: false)
      expect(described_class.connect).to be(false)
    end
  end

  describe 'execute_query(sql:, **params)' do
    it 'raises an error if the database connection has not been established' do
      mock_active_record_base(success: false)
      msg = Uc3DmpRds::Adapter::MSG_NO_CONNECTION
      expect { described_class.execute_query(sql: 'foo') }.to raise_error(StandardError, msg)
    end

    it 'returns an empty array if :sql is not a String' do
      sql = 123
      expect(described_class.execute_query(sql: sql)).to eql([])
    end

    it 'returns an empty array if :sql is empty' do
      sql = '    '
      expect(described_class.execute_query(sql: sql)).to eql([])
    end

    it 'raises an error if the :_verify_params returns false' do
      allow(described_class).to receive(:_verify_params).and_return(false)
      msg = described_class::MSG_KEYWORDS_INVALID
      expect { described_class.execute_query(sql: 'foo = :foo', bar: 'foo') }.to raise_error(StandardError, msg)
    end

    it 'executes the query if :params is nil and :sql has no params' do
      allow(described_class).to receive(:_verify_params).and_return(true)
      mock_active_record_base(success: true)
      sql = 'SELECT * FROM table;'
      expect(described_class.execute_query(sql: sql)).to eql(%w[foo bar])
    end

    it 'executes the query when :params has params' do
      allow(described_class).to receive(:_verify_params).and_return(true)
      mock_active_record_base(success: true)
      sql = 'SELECT * FROM table WHERE col1 = :foo AND col2 = :bar'
      params = { bar: 'bar', foo: 'foo' }
      expect(described_class.execute_query(sql: sql, **params)).to eql(%w[foo bar])
    end
  end

  describe '_credentials' do
    it 'calls SSM parameter store to fetch the credentials' do
      expect(described_class.send(:_credentials)).to eql({ username: 'foo', password: 'bar' })
    end

    it 'raises errors received from Uc3DmpApiCore::SsmReader' do
      allow(Uc3DmpApiCore::SsmReader).to receive(:get_ssm_value).and_raise(aws_error)
      expect { described_class.send(:_credentials) }.to raise_error(Aws::Errors::ServiceError, 'Testing')
    end
  end

  describe '_verify_params(sql:, params:)' do
    it 'returns false if :params is not a Hash and :sql has no params defined' do
      sql = 'SELECT * FROM table'
      expect(described_class.send(:_verify_params, sql: sql, params: 123)).to be(true)
    end

    it 'returns false if :params is not an empty Hash and :sql has no params defined' do
      sql = 'SELECT * FROM table'
      params = { foo: 'foo' }
      expect(described_class.send(:_verify_params, sql: sql, params: params)).to be(false)
    end

    it 'returns false if :sql has params and :params is not a Hash' do
      sql = 'SELECT * FROM table WHERE foo = :foo'
      expect(described_class.send(:_verify_params, sql: sql, params: 123)).to be(false)
    end

    it 'returns false if :sql has params and :params is an empty Hash' do
      sql = 'SELECT * FROM table WHERE foo = :foo'
      expect(described_class.send(:_verify_params, sql: sql, params: {})).to be(false)
    end

    it 'returns false if the :params include a param that is not in the :sql' do
      sql = 'SELECT * FROM table WHERE col1 = :foo AND col2 = :bar'
      params = { foo: 'foo', bar: 'bar', baz: 'baz' }
      expect(described_class.send(:_verify_params, sql: sql, params: params)).to be(false)
    end

    it 'returns false if the :sql includes a param that is not in the :params' do
      sql = 'SELECT * FROM table WHERE col1 = :foo AND col2 = :bar'
      params = { bar: 'bar', baz: 'baz' }
      expect(described_class.send(:_verify_params, sql: sql, params: params)).to be(false)
    end

    it 'returns true if all the :params match all the params in :sql' do
      sql = 'SELECT * FROM table WHERE col1 = :foo AND col2 = :bar'
      params = { foo: 'foo', bar: 'bar' }
      expect(described_class.send(:_verify_params, sql: sql, params: params)).to be(true)
    end
  end
end
