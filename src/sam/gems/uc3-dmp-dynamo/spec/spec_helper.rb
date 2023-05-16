# frozen_string_literal: true

require 'bundler/setup'
require 'ostruct'

Dir["#{Dir.getwd}/lib/uc3-dmp-dynamo/*.rb"].sort.each { |f| require f }

require_relative 'support/shared'

ENV['AWS_REGION'] = 'us-west-2'
ENV['LAMBDA_ENV'] = 'test'

# Ensure that the ENV fetch of the TABLE_NAME is mocked
ENV['DYNAMO_TABLE'] = 'test-table'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end