# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'uc3-dmp-id/version'

Gem::Specification.new do |spec|
  spec.name        = 'uc3-dmp-id'
  spec.version     = Uc3DmpId::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Brian Riley']
  spec.email       = ['brian.riley@ucop.edu']

  spec.summary     = 'DMPTool gem that provides support for DMP ID records'
  spec.description = 'Helpers for working with JSON that represents a DMP ID'
  spec.homepage    = 'https://github.com/CDLUC3/dmp-hub-cfn/blob/main/src/sam/gems/uc3-dmp-id'
  spec.license     = 'MIT'

  spec.files         = Dir['lib/**/*'] + Dir['schemas/*.json'] + %w[README.md]
  spec.require_paths = ['lib', 'schemas']
  spec.required_ruby_version = '>= 2.7'

  spec.add_runtime_dependency('json', '~> 2.6')
  spec.add_runtime_dependency('json-schema', '~> 3.0')
  spec.add_runtime_dependency('logger', '~> 1.4')

  spec.add_runtime_dependency('uc3-dmp-dynamo', '~> 0.0')

  # Requirements for running RSpec
  spec.add_development_dependency('byebug', '11.1.3')
  spec.add_development_dependency('rspec', '3.9.0')
  spec.add_development_dependency('rubocop', '1.50.2')
  spec.add_development_dependency('rubocop-rspec', '2.20.0')

  spec.metadata['rubygems_mfa_required'] = 'false'
end
