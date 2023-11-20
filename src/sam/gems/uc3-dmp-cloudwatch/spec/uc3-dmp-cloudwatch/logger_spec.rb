# frozen_string_literal: true

# Require the necessary libraries and the Logger class
require 'spec_helper'

RSpec.describe 'Uc3DmpCloudwatch::Logger' do
  let!(:described_class) { Uc3DmpCloudwatch::Logger }

  describe 'initialization' do
    it 'initializes with default level "info" if no level is provided' do
      logger = described_class.new
      expect(logger.level).to eq('info')
    end

    it 'initializes with the provided level' do
      logger = described_class.new(level: 'error')
      expect(logger.level).to eq('error')
    end
  end

  describe 'error' do
    it 'logs an error message' do
      logger = described_class.new
      expected = "ERROR  MESSAGE: An error occurred\nerror  Event: \n"
      expect { logger.error(message: 'An error occurred') }.to output(expected).to_stdout
    end

    it 'logs additional details for error' do
      logger = described_class.new
      expected = "ERROR  MESSAGE: An error occurred\nERROR  PAYLOAD: {:key=>\"value\"}\nerror  Event: \n"
      expect { logger.error(message: 'An error occurred', details: { key: 'value' }) }.to output(expected).to_stdout
    end
  end

  describe 'info' do
    it 'logs an info message' do
      logger = described_class.new(level: 'info')
      expected = "INFO  MESSAGE: Information\n"
      expect { logger.info(message: 'Information') }.to output(expected).to_stdout
    end

    it 'logs additional details for info' do
      logger = described_class.new(level: 'info')
      expected = "INFO  MESSAGE: Information\nINFO  PAYLOAD: {:key=>\"value\"}\n"
      expect { logger.info(message: 'Information', details: { key: 'value' }) }.to output(expected).to_stdout
    end
  end

  describe 'debug' do
    it 'logs a debug message' do
      logger = described_class.new(level: 'debug')
      expected = "DEBUG  MESSAGE: Debugging\n"
      expect { logger.debug(message: 'Debugging') }.to output(expected).to_stdout
    end

    it 'logs additional details for debug' do
      logger = described_class.new(level: 'debug')
      expected = "DEBUG  MESSAGE: Debugging\nDEBUG  PAYLOAD: {:key=>\"value\"}\n"
      expect { logger.debug(message: 'Debugging', details: { key: 'value' }) }.to output(expected).to_stdout
    end
  end
end
