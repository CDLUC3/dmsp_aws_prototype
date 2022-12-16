# frozen_string_literal: true

require 'json'
require 'json-schema'

# ------------------------------------------------------------------------------------
# Validator
#
# Shared helper methods for Lambdas that will validate the structure of inoming JSON
# ------------------------------------------------------------------------------------
class Validator
  # Valid Validation modes are:
  #   - :author --> system of provenance is attempting to create or update
  #   - :delete --> system of provenance is attempting to delete/tombstone
  #   - :amend  --> a non-provenance system is attempting to update
  VALIDATION_MODES = %w[author amend delete].freeze

  class << self
    # Validate the specified DMP's :json against the schema for the specified :mode
    #
    # ------------------------------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def validate(mode:, json:)
      json = parse_json(json: json)
      return { valid: false, errors: [Messages::MSG_EMPTY_JSON] } if json.nil? || !VALIDATION_MODES.include?(mode)

      # Load the appropriate JSON schema for the mode
      schema = _load_schema(mode: mode)
      return { valid: false, errors: [Messages::MSG_NO_SCHEMA] } if schema.nil?

      # Validate the JSON
      errors = JSON::Validator.fully_validate(schema, json)
      errors = errors.map { |err| err.gsub('The property \'#/\' ', '') }
      errors = ([Messages::MSG_INVALID_JSON] << errors).flatten.compact.uniq unless errors.empty?
      { valid: errors.empty?, errors: errors.map { |err| err.gsub(/in schema [a-z0-9\-]+/, '').strip } }
    rescue JSON::Schema::ValidationError => e
      { valid: false, errors: [format(Messages::MSG_BAD_JSON, msg: e.message)] }
    end
    # rubocop:enable Metrics/AbcSize

    # Parse the incoming JSON if necessary or return as is if it's already a Hash
    # ------------------------------------------------------------------------------------
    def parse_json(json:)
      return json if json.is_a?(Hash)

      json.is_a?(String) ? JSON.parse(json) : nil
    rescue JSON::ParserError
      nil
    end

    # ------------------------------------------------------------------------------------
    # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS MODULE
    # ------------------------------------------------------------------------------------

    # Load the JSON schema that corresponds with the mode
    # ------------------------------------------------------------------------------------
    def _load_schema(mode:)
      schema = "#{_schema_dir}/config/#{mode}.json"
      file = schema if File.exist?(schema)
      return nil if mode.nil? || file.nil? || !File.exist?(file)

      JSON.parse(File.read(file))
    rescue JSON::ParserError
      nil
    end

    # The location of th JSON schema files
    # ------------------------------------------------------------------------------------
    def _schema_dir
      '/opt/ruby'
    end
  end
end
