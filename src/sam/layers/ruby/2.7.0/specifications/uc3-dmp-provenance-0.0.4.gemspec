# -*- encoding: utf-8 -*-
# stub: uc3-dmp-provenance 0.0.4 ruby lib

Gem::Specification.new do |s|
  s.name = "uc3-dmp-provenance".freeze
  s.version = "0.0.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "rubygems_mfa_required" => "false" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Brian Riley".freeze]
  s.date = "2023-05-09"
  s.description = "Helpers for working with JSON that represents a provenance system (e.g. DMPTool or NIH API)".freeze
  s.email = ["brian.riley@ucop.edu".freeze]
  s.homepage = "https://github.com/CDLUC3/dmp-hub-cfn/blob/main/src/sam/gems/uc3-dmp-provenance".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7".freeze)
  s.rubygems_version = "3.1.6".freeze
  s.summary = "DMPTool gem that provides support for Provenance records".freeze

  s.installed_by_version = "3.1.6" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<json>.freeze, ["~> 2.6"])
    s.add_runtime_dependency(%q<logger>.freeze, ["~> 1.4"])
    s.add_runtime_dependency(%q<uc3-dmp-dynamo>.freeze, ["~> 0.0"])
    s.add_development_dependency(%q<byebug>.freeze, ["= 11.1.3"])
    s.add_development_dependency(%q<rspec>.freeze, ["= 3.9.0"])
    s.add_development_dependency(%q<rubocop>.freeze, ["= 1.50.2"])
    s.add_development_dependency(%q<rubocop-rspec>.freeze, ["= 2.20.0"])
  else
    s.add_dependency(%q<json>.freeze, ["~> 2.6"])
    s.add_dependency(%q<logger>.freeze, ["~> 1.4"])
    s.add_dependency(%q<uc3-dmp-dynamo>.freeze, ["~> 0.0"])
    s.add_dependency(%q<byebug>.freeze, ["= 11.1.3"])
    s.add_dependency(%q<rspec>.freeze, ["= 3.9.0"])
    s.add_dependency(%q<rubocop>.freeze, ["= 1.50.2"])
    s.add_dependency(%q<rubocop-rspec>.freeze, ["= 2.20.0"])
  end
end