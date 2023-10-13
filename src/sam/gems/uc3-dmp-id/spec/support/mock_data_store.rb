# frozen_string_literal: true

module Uc3DmpDynamo
  # Mock The Uc3DmpDynamo Client functionality so we can inspect what the DMP ID looks like
  # rubocop:disable Lint/UnusedMethodArgument
  class Client
    attr_accessor :data_store

    def initialize(**_args)
      @data_store = []
    end

    def pk_exists?(key:, logger: nil)
      return false unless @data_store.any?

      @data_store.any? { |rec| rec['PK'] == key['PK'] }
    end

    def get_item(key:, logger: nil)
      return nil unless @data_store.any?

      @data_store.find { |rec| rec['PK'] == key[:PK] && rec['SK'] == key[:SK] }
    end

    # rubocop:disable Metrics/AbcSize
    def query(args:, logger: nil)
      dmps = []

      conds = args.fetch(:key_conditions, {})
      unless conds[:owner_orcid].nil?
        dmps = @data_store.find { |rec| rec['dmphub_owner_id'] == conds[:owner_orcid][:attribute_value_list].first }
      end
      unless conds[:owner_org_ror].nil?
        dmps = @data_store.find { |rec| rec['dmphub_owner_org'] == conds[:owner_org_ror][:attribute_value_list].first }
      end
      unless conds[:modification_day].nil?
        dmps = @data_store.find do |rec|
          rec['dmphub_modification_day'] == conds[:modification_day][:attribute_value_list].first
        end
      end
      dmps = @data_store.select { |rec| rec['PK'] == conds[:PK][:attribute_value_list].first } unless conds[:PK].nil?
      dmps
    end
    # rubocop:enable Metrics/AbcSize

    def put_item(json:, logger: nil)
      rec = @data_store.find { |r| r['PK'] == json['PK'] && r['SK'] == json['SK'] }
      delete_item(p_key: json['PK'], s_key: json['SK']) unless rec.nil?

      @data_store << json
    end

    def delete_item(p_key:, s_key:, logger: nil)
      @data_store = @data_store.reject { |rec| rec['PK'] == p_key && rec['SK'] == s_key }
    end

    def change_timestamps(p_key:, tstamp:)
      rec = @data_store.find { |r| r['PK'] == p_key && r['SK'] == Uc3DmpId::Helper::DMP_LATEST_VERSION }
      return false if rec.nil?

      json = rec.dup
      delete_item(p_key:, s_key: rec['SK'])
      json['created'] = tstamp
      json['modified'] = tstamp
      json['dmphub_modification_day'] = Time.parse(tstamp).strftime('%Y-%,-%d')
      @data_store << json
    end
  end
  # rubocop:enable Lint/UnusedMethodArgument
end
