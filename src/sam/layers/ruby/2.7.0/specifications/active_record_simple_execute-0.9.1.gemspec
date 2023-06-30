# -*- encoding: utf-8 -*-
# stub: active_record_simple_execute 0.9.1 ruby lib

Gem::Specification.new do |s|
  s.name = "active_record_simple_execute".freeze
  s.version = "0.9.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/westonganger/active_record_simple_execute/blob/master/CHANGELOG.md", "source_code_uri" => "https://github.com/westonganger/active_record_simple_execute" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Weston Ganger".freeze]
  s.date = "2023-02-14"
  s.description = "Sanitize and Execute your raw SQL queries in ActiveRecord and Rails with a much more intuitive and shortened syntax.".freeze
  s.email = ["weston@westonganger.com".freeze]
  s.homepage = "https://github.com/westonganger/active_record_simple_execute".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3".freeze)
  s.rubygems_version = "3.1.6".freeze
  s.summary = "Sanitize and Execute your raw SQL queries in ActiveRecord and Rails with a much more intuitive and shortened syntax.".freeze

  s.installed_by_version = "3.1.6" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<activerecord>.freeze, [">= 3.2"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_development_dependency(%q<minitest-reporters>.freeze, [">= 0"])
    s.add_development_dependency(%q<sqlite3>.freeze, [">= 0"])
    s.add_development_dependency(%q<rails>.freeze, [">= 0"])
    s.add_development_dependency(%q<appraisal>.freeze, [">= 0"])
    s.add_development_dependency(%q<warning>.freeze, [">= 0"])
  else
    s.add_dependency(%q<activerecord>.freeze, [">= 3.2"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<minitest>.freeze, [">= 0"])
    s.add_dependency(%q<minitest-reporters>.freeze, [">= 0"])
    s.add_dependency(%q<sqlite3>.freeze, [">= 0"])
    s.add_dependency(%q<rails>.freeze, [">= 0"])
    s.add_dependency(%q<appraisal>.freeze, [">= 0"])
    s.add_dependency(%q<warning>.freeze, [">= 0"])
  end
end
