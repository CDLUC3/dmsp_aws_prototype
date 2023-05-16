# frozen_string_literal: true

module Uc3DmpId
  class Uc3DmpIdValidatorError < StandardError; end

  class Validator
    # Valid Validation modes are:
    #   - :author --> system of provenance is attempting to create or update
    #   - :delete --> system of provenance is attempting to delete/tombstone
    #   - :amend  --> a non-provenance system is attempting to update
    VALIDATION_MODES = %w[author amend delete].freeze

    MSG_EMPTY_JSON = 'JSON was empty or was not a valid JSON document!'
    MSG_INVALID_JSON = 'Invalid JSON.'
    MSG_NO_SCHEMA = 'No JSON schema available!'
    MSG_BAD_JSON = 'Fatal validation error: %{msg} - %{trace}'
    MSG_VALID_JSON = 'The JSON is valid.'

    class << self
      # Validate the specified DMP's :json against the schema for the specified :mode
      #
      # ------------------------------------------------------------------------------------
      def validate(mode:, json:)
        json = Helper.parse_json(json: json)
        return [MSG_EMPTY_JSON] if json.nil? || !VALIDATION_MODES.include?(mode)

        # Load the appropriate JSON schema for the mode
        schema = _load_schema(mode: mode)
        return [MSG_NO_SCHEMA] if schema.nil?

        # Validate the JSON
        errors = JSON::Validator.fully_validate(schema, json)
        errors = errors.map { |err| err.gsub('The property \'#/\' ', '') }
        errors = ([MSG_INVALID_JSON] << errors).flatten.compact.uniq unless errors.empty?
        errors.map { |err| err.gsub(/in schema [a-z0-9-]+/, '').strip }
      rescue JSON::Schema::ValidationError => e
        raise Uc3DmpIdValidatorError, MSG_BAD_JSON % { msg: e.message, trace: e.backtrace }
      end

      # ------------------------------------------------------------------------------------
      # METHODS BELOW ARE ONLY MEANT TO BE INVOKED FROM WITHIN THIS MODULE
      # ------------------------------------------------------------------------------------

      # Load the JSON schema that corresponds with the mode
      # ------------------------------------------------------------------------------------
      def _load_schema(mode:)
        schema = "#{_schema_dir}/schemas/#{mode}.json"
        file = schema if File.exist?(schema)
        return nil if mode.nil? || file.nil? || !File.exist?(file)

        JSON.parse(File.read(file))
      rescue JSON::ParserError
        nil
      end

      # The location of th JSON schema files
      # ------------------------------------------------------------------------------------
      def _schema_dir
        # TODO: Switch this to the gem dirctory, not sure if this is the same as the Layer below
        '/opt/ruby'
      end
    end
  end
end
