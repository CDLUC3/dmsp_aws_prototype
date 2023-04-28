# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'uc3-dmp-api-core/version'

Gem::Specification.new do |spec|
  spec.name        = 'uc3-dmp-api-core'
  spec.version     = Uc3DmpApiCore::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Brian Riley']
  spec.email       = ['brian.riley@ucop.edu']

  spec.summary     = 'DMPTool gem that provides general support for Lambda functions'
  spec.description = 'Helpers for SSM, EventBridge, standardizing responses/errors'
  spec.homepage    = 'https://github.com/CDLUC3/dmp-hub-cfn/blob/main/src/sam/gems/uc3-dmp-api-core'
  spec.license     = 'MIT'

  spec.files         = Dir['lib/**/*'] + %w[README.md]
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.7'

  spec.add_runtime_dependency('json', '~> 2.6')
  spec.add_runtime_dependency('logger', '~> 1.4')

  spec.add_runtime_dependency('aws-sdk-sns', '~> 1.60')
  spec.add_runtime_dependency('aws-sdk-ssm', '~> 1.150')

  # Requirements for running RSpec
  spec.add_development_dependency('byebug', '11.1.3')
  spec.add_development_dependency('rspec', '3.9.0')
  spec.add_development_dependency('rubocop', '0.88.0')
end
