# frozen_string_literal: true

require 'aws-sdk-dynamodb'

require 'key_helper'
require 'messages'
require 'responder'
require 'ssm_reader'

# -------------------------------------------------------------------------
# Dynamo Table Helper for creating new DMP items
#
# Shared helper methods for Lambdas that interact with the DynamoDB Table
# -------------------------------------------------------------------------
class DmpFinder
  attr_accessor :provenance, :table, :client, :debug

  def initialize(**args)
    @provenance = args[:provenance] || {}
    @table = args.fetch(:table_name, SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME))
    @client = args.fetch(:client, Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil)))
    @debug = args.fetch(:debug_mode, false)
  end

  # Fetch the DMPs for the provenance
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize

  # TODO: Replace this with ElasticSearch

  def dmps_for_provenance
    # Fail if the provenance is not defined
    return { status: 403, error: Messages::MSG_DMP_FORBIDDEN } if !@provenance.is_a?(Hash) ||
                                                                  @provenance['PK'].nil?

    p_key = @provenance['PK']
    response = @client.query(
      {
        table_name: @table,
        key_conditions: {
          PK: { attribute_value_list: ["#{KeyHelper::PK_PROVENANCE_PREFIX}#{p_key}"], comparison_operator: 'EQ' },
          SK: { attribute_value_list: ['DMPS'], comparison_operator: 'EQ' }
        }
      }
    )
    { status: 200, items: response.items.map { |item| JSON.parse({ dmp: item.item }.to_json) }.compact.uniq }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: 'DmpFinder.dmps_for_provenance', message: e.message,
                        details: ([provenance] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize

  # Search the DMPs based on the args
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/MethodLength

  # TODO: Replace this with ElasticSearch

  def search_dmps(**_args)
    # TODO: Need to handle pagination here!!
    #       see: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Scan.html#Scan.Pagination
    response = @client.scan(
      {
        table_name: @table,
        limit: Responder::MAXIMUM_PER_PAGE,
        scan_filter: {
          SK: {
            attribute_value_list: [KeyHelper::DMP_LATEST_VERSION],
            comparison_operator: 'EQ'
          }
        },
        expression_attribute_names: {
          '#dmp_id': 'dmp_id',
          '#title': 'title',
          '#contact': 'contact',
          '#created': 'created',
          '#updated': 'updated'
        },
        projection_expression: '#title, #dmp_id, #contact, #created, #updated'
      }
    )
    { status: 200, items: response.items.map { |item| JSON.parse({ dmp: item.item }.to_json) }.compact.uniq }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: 'DmpFinder.dmps_for_provenance', message: e.message,
                        details: ([provenance] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/MethodLength

  # Find a DMP based on the contents of the incoming JSON
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def find_dmp_by_json(json:)
    json = Validator.parse_json(json: json)&.fetch('dmp', {})
    return { status: 400, error: "#{Messages::MSG_INVALID_ARGS} - by json" } if json.nil? ||
                                                                                (json['PK'].nil? && json['dmp_id'].nil?)

    p_key = json['PK']
    # Translate the incoming :dmp_id into a PK
    p_key = KeyHelper.dmp_id_to_pk(json: json.fetch('dmp_id', {})) if p_key.nil?

    # find_by_PK
    response = find_dmp_by_pk(p_key: p_key, s_key: json['SK']) unless p_key.nil?
    return response unless response[:status] == 404

    # find_by_dmphub_provenance_id -> if no PK and no dmp_id result
    find_dmp_by_dmphub_provenance_identifier(json: json)
  end
  # rubocop:enable Metrics/AbcSize

  # Find the DMP's versions
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def find_dmp_versions(p_key:)
    source = "DmpFinder.find_dmp_versions - PK: #{p_key}"
    return { status: 400, error: "#{Messages::MSG_INVALID_ARGS} - versions" } if p_key.nil?

    response = @client.query(
      {
        table_name: @table,
        key_conditions: {
          PK: { attribute_value_list: [KeyHelper.append_pk_prefix(dmp: p_key)], comparison_operator: 'EQ' }
        },
        scan_index_forward: false, # Sort by SK descending,
        projection_expression: 'modified',
        consistent_read: false,
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    log_message(source: source, message: 'Search for versions by PK', details: response.items) if @debug
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if response.items.nil? || response.items.empty?

    items = response.items.map { |item| JSON.parse({ dmp: item }.to_json) }.compact.uniq
    { status: 200, items: items }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([provenance] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Find the DMP by its PK and SK
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize
  def find_dmp_by_pk(p_key:, s_key: KeyHelper::DMP_LATEST_VERSION)
    source = "DmpFinder.find_dmp_by_pk - PK: #{p_key}, SK: #{s_key}"
    return { status: 400, error: "#{Messages::MSG_INVALID_ARGS} - by pk" } if p_key.nil?

    s_key = KeyHelper::DMP_LATEST_VERSION if s_key.nil? || s_key.strip == ''
    response = @client.get_item(
      {
        table_name: @table,
        key: { PK: p_key, SK: s_key },
        consistent_read: false,
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    log_message(source: source, message: 'Search by PK', details: response.items) if @debug
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if response[:item].nil? || response[:item].empty?

    { status: 200, items: [JSON.parse({ dmp: response[:item] }.to_json)] }
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([provenance] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize

  # Attempt to find the DMP item by the provenance system's identifier
  # -------------------------------------------------------------------------
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def find_dmp_by_dmphub_provenance_identifier(json:)
    source = 'DmpFinder.find_dmp_by_dmphub_provenance_identifier'
    return { status: 400, error: "#{Messages::MSG_INVALID_ARGS} - by prov" } if json.nil? ||
                                                                                json.fetch('dmp_id',
                                                                                           {})['identifier'].nil?

    response = @client.query(
      {
        table_name: @table,
        index_name: 'dmphub_provenance_identifier_gsi',
        key_conditions: {
          dmphub_provenance_identifier: {
            attribute_value_list: [json['dmp_id']['identifier']],
            comparison_operator: 'EQ'
          }
        },
        filter_expression: 'SK = :version',
        expression_attribute_values: { ':version': KeyHelper::DMP_LATEST_VERSION },
        return_consumed_capacity: @debug ? 'TOTAL' : 'NONE'
      }
    )
    log_message(source: source, message: 'Search by provenance identifier', details: response.items) if @debug
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if response.nil?

    items = response.items.map { |item| JSON.parse({ dmp: item.item }.to_json) }.compact.uniq
    return { status: 404, error: Messages::MSG_DMP_NOT_FOUND } if items.empty?

    # If we got a hit, fetch the DMP and return it.
    find_dmp_by_pk(p_key: items.first['dmp']['PK'], s_key: items.first['dmp']['SK'])
  rescue Aws::Errors::ServiceError => e
    Responder.log_error(source: source, message: e.message,
                        details: ([provenance, json.inspect] << e.backtrace).flatten)
    { status: 500, error: Messages::MSG_SERVER_ERROR }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # Build the dmphub_versions array and attach it to the dmp
  # rubocop:disable Metrics/AbcSize
  def append_versions(p_key:, dmp:)
    return dmp if p_key.nil? || !dmp.is_a?(Hash)

    result = find_dmp_versions(p_key: p_key)
    return dmp unless result[:status] == 200 && result[:items].length > 1

    versions = result[:items].map do |version|
      next if version.fetch('dmp', {})['modified'].nil?

      timestamp = version['dmp']['modified']
      {
        timestamp: timestamp,
        url: "#{KeyHelper.api_base_url}dmps/#{KeyHelper.remove_pk_prefix(dmp: p_key)}?version=#{timestamp}"
      }
    end
    dmp['dmphub_versions'] = JSON.parse(versions.to_json)
    dmp
  end
  # rubocop:enable Metrics/AbcSize
end
