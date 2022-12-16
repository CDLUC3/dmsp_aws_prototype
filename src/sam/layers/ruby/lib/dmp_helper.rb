# frozen_string_literal: true

# ---------------------------------------------------------------------------------
# Helper methods for DMP items
#
# Shared helper methods for the dmp_[creator|updater|deleter].rb files and Lambdas
# ---------------------------------------------------------------------------------
class DmpHelper
  class << self
    # Equality check which will determine if the DMPs are equal.
    #   This ignores :SK, :dmphub_modification_day and :dmphub_updated_at attributes
    # --------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def dmps_equal?(dmp_a:, dmp_b:)
      # If the PK do not match, then they are not equivalent!
      return false unless dmp_a.is_a?(Hash) && dmp_a.fetch('PK', '').start_with?(KeyHelper::PK_DMP_PREFIX) &&
                          dmp_b.is_a?(Hash) && dmp_b.fetch('PK', '').start_with?(KeyHelper::PK_DMP_PREFIX) &&
                          dmp_a['PK'] == dmp_b['PK']
      # return true if they're identical
      return true if dmp_a == dmp_b

      a = deep_copy_dmp(obj: dmp_a)
      b = deep_copy_dmp(obj: dmp_b)

      # ignore some of the attributes before comparing
      %w[SK dmphub_modification_day dmphub_updated_at dmphub_created_at].each do |key|
        a.delete(key) unless a[key].nil?
        b.delete(key) unless b[key].nil?
      end
      a == b
    end
    # rubocop:enable Metrics/AbcSize

    # Add all attributes necessary for the DMPHub
    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    # --------------------------------------------------------------
    def annotate_dmp(provenance:, p_key:, json:)
      return nil if !provenance.is_a?(Hash) || p_key.nil? || json.nil? || provenance['PK'].nil?

      # Fail the json as is if the :PK does not match the :dmp_id if the json has a :PK
      id = KeyHelper.dmp_id_to_pk(json: json.fetch('dmp_id', {}))
      return json if id != p_key && !json['PK'].nil?

      annotated = deep_copy_dmp(obj: json)
      annotated['PK'] = json['PK'] || p_key
      annotated['SK'] = KeyHelper::DMP_LATEST_VERSION

      # Ensure that the :dmp_id matches the :PK
      annotated['dmp_id'] = KeyHelper.pk_to_dmp_id(p_key: annotated['PK'])

      # Update the modification timestamps
      annotated['dmphub_modification_day'] = Time.now.strftime('%Y-%m-%d')
      annotated['dmphub_updated_at'] = Time.now.iso8601
      # Only add the Creation date if it is blank
      annotated['dmphub_created_at'] = Time.now.iso8601 if json['dmphub_created_at'].nil?
      return annotated unless json['dmphub_provenance_id'].nil?

      annotated['dmphub_provenance_id'] = provenance.fetch('PK', '')
      return annotated if !annotated['dmphub_provenance_identifier'].nil? ||
                          json.fetch('dmp_id', {})['identifier'].nil?

      # Record the original Provenance system's identifier
      annotated['dmphub_provenance_identifier'] = KeyHelper.format_provenance_id(
        provenance: provenance, value: json.fetch('dmp_id', {})['identifier']
      )
      annotated
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # Ruby's clone/dup methods do not clone/dup the children, so we need to do it here
    # --------------------------------------------------------------
    # rubocop:disable Metrics/AbcSize
    def deep_copy_dmp(obj:)
      case obj.class.name
      when 'Array'
        obj.map { |item| deep_copy_dmp(obj: item) }
      when 'Hash'
        hash = obj.dup
        hash.each_pair do |key, value|
          if key.is_a?(::String) || key.is_a?(::Symbol)
            hash[key] = deep_copy_dmp(obj: value)
          else
            hash.delete(key)
            hash[deep_copy_dmp(obj: key)] = deep_copy_dmp(obj: value)
          end
        end
        hash
      else
        obj.dup
      end
    end
    # rubocop:enable Metrics/AbcSize
  end
end
