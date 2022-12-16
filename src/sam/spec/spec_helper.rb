# frozen_string_literal: true

require 'bundler/setup'
require 'ostruct'

my_gem_path = Dir["#{Dir.getwd}/layers/ruby/gems/**/lib/"]
$LOAD_PATH.unshift(*my_gem_path)

# Lambda functions require us to add the Lambda layer ruby files into the LOAD_PATH
layer_path = Dir["#{Dir.getwd}/layers/ruby/lib/"]
$LOAD_PATH.unshift(*layer_path)

# rubocop:disable Lint/NonDeterministicRequireOrder
# RSpec tests require us to load the files and require them
Dir["#{Dir.getwd}/layers/ruby/lib/*.rb"].each { |f| require f }

# Require the lambda functions
Dir["#{Dir.getwd}/functions/**/*.rb"].each { |f| require f }
# rubocop:enable Lint/NonDeterministicRequireOrder

require_relative 'support/shared'

ENV['AWS_REGION'] = 'us-west-2'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
