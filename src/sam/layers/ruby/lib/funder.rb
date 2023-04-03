# frozen_string_literal: true

require 'active_record'
require 'mysql2'

# Represents a ROR Funder record
class Funder < ApplicationRecord
  table_name 'registry_orgs'

  default_scope { where.not(fundref_id: nil) }

  scope :search, lambda { |term|
    by_name(term).or(by_acronym(term)).or(by_alias(term)).or(by_domain(term))
  }

  # Scopes to search specific information on the ROR record
  scope :by_name, lambda { |term|
    where('LOWER(registry_orgs.name) LIKE LOWER(?)', "%#{term}%")
  }

  scope :by_domain, lambda { |term|
    where('LOWER(registry_orgs.home_page) LIKE LOWER(?)', "%#{term}%")
  }

  scope :by_acronym, lambda { |term|
    where(safe_json_lower_where_clause(table: 'registry_orgs', attribute: 'acronyms'),
          "%\"#{term}\"%")
  }

  scope :by_alias, lambda { |term|
    where(safe_json_lower_where_clause(table: 'registry_orgs', attribute: 'aliases'),
          "%\"#{term}\"%")
  }

  # Check to see if the Funder has an API definition
  def has_api?
    !api_target.nil?
  end

  # Convert the ActiveRecord model into a JSON Object
  def to_json
    hash = { name: name, funder_id: { identifier: fundref_id, type: 'fundref' } }
    return hash.to_json unless has_api?

    hash[:funder_api] = "api.dmphub-dev.cdlib.org/funders/#{fundref_id}/api"
    hash[:funder_api_label] = api_label
    hash[:funder_api_guidance] = api_guidance
    hash.to_json
  end
end
