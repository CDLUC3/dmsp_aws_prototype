# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'uc3-dmp-provenance/version'

Gem::Specification.new do |spec|
  spec.name        = 'uc3-dmp-provenance'
  spec.version     = Uc3DmpProvenance::VERSION
  spec.platform    = Gem::Platform::RUBY
  spec.authors     = ['Brian Riley']
  spec.email       = ['brian.riley@ucop.edu']

  spec.summary     = 'DMPTool gem that provides support for Provenance records'
  spec.description = 'Helpers for working with JSON that represents a provenance system (e.g. DMPTool or NIH API)'
  spec.homepage    = 'https://github.com/CDLUC3/dmp-hub-cfn/blob/main/src/sam/gems/uc3-dmp-provenance'
  spec.license     = 'MIT'

  spec.files         = Dir['lib/**/*'] + %w[README.md]
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.2'

  spec.add_runtime_dependency('json', '~> 2.6')

  spec.add_runtime_dependency('uc3-dmp-cognito', '~> 0.0')
  spec.add_runtime_dependency('uc3-dmp-dynamo', '~> 0.0')

  # Requirements for running RSpec
  spec.add_development_dependency('byebug', '11.1.3')
  spec.add_development_dependency('rspec', '3.9.0')
  spec.add_development_dependency('rubocop', '1.50.2')
  spec.add_development_dependency('rubocop-rspec', '2.20.0')

  spec.metadata['rubygems_mfa_required'] = 'false'
end
