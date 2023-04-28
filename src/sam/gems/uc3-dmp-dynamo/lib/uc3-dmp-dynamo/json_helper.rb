# frozen_string_literal: true


# TODO: Be sure to update the API functions so that they call cleanse_dmp_json before
#       calling Uc3DmpApiCore::Responder.respond !!!!!!!!!!


module Uc3DmpDynamo
  # Helper functions for working with Dynamo JSON
  class JsonHelper
    class << self
      # Recursive method that strips out any DMPHub related metadata from a DMP record before sending
      # it to the caller
      # --------------------------------------------------------------------------------
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def cleanse_dmp_json(json:)
        return json unless json.is_a?(Hash) || json.is_a?(Array)

        # If it's an array clean each of the objects individually
        return json.map { |obj| cleanse_dmp_json(json: obj) }.compact if json.is_a?(Array)

        cleansed = {}
        allowable = %w[dmphub_versions]
        json.each_key do |key|
          next if (key.to_s.start_with?('dmphub') && !allowable.include?(key)) || %w[PK SK].include?(key.to_s)

          obj = json[key]
          # If this object is a Hash or Array then recursively cleanse it
          cleansed[key] = obj.is_a?(Hash) || obj.is_a?(Array) ? cleanse_dmp_json(json: obj) : obj
        end
        cleansed.keys.any? ? cleansed : nil
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    end
  end
end
