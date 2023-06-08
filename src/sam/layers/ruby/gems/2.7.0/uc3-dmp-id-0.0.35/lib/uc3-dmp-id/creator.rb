# frozen_string_literal: true

require 'securerandom'

module Uc3DmpId
  class CreatorError < StandardError; end

  class Creator
    MSG_NO_BASE_URL = 'No base URL found for DMP ID (e.g. `doi.org`)'
    MSG_NO_SHOULDER = 'No DOI shoulder found. (e.g. `10.12345/`)'
    MSG_UNABLE_TO_MINT = 'Unable to mint a unique DMP ID.'

    class << self
      def create(provenance:, owner_org:, json:, debug: false)
        raise CreatorError, MSG_NO_SHOULDER if ENV['DMP_ID_SHOULDER'].nil?
        raise CreatorError, MSG_NO_BASE_URL if ENV['DMP_ID_BASE_URL'].nil?

        # Fail if the provenance is not defined
        raise DeleterError, MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil?

        # Validate the incoming JSON first
        errs = Validator.validate(mode: 'author', json: Helper.parse_json(json: json))
        raise CreatorError, errs.join(', ') if errs.is_a?(Array) && errs.any? && errs.first != Validator::MSG_VALID_JSON

        # Fail if the provenance or owner affiliation are not defined
        raise CreatorError, MSG_NO_PROVENANCE_OWNER if provenance.nil? || owner_org.nil?
        raise CreatorError, MSG_NO_OWNER_ORG unless owner_org.is_a?(String) && !owner_org.strip.empty?

        # Try to find it first and Fail if found
        result = Finder.by_json(json: json, debug: debug)
        raise CreatorError, Uc3DmpId::MSG_DMP_EXISTS if result.is_a?(Hash)

        p_key = _preregister_dmp_id(json: json, debug: debug)
        raise CreatorError, MSG_UNABLE_TO_MINT if p_key.nil?

        # Add the DMPHub specific attributes and then save
        annotated = Helper.annotate_dmp_json(provenance: provenance, owner_org: owner_org, p_key: p_key, json: json)
        puts "CREATING DMP ID:" if debug
        puts annotated if debug

        # Create the item
        client = Uc3DmpDynamo::Client.new(debug: debug)
        resp = client.put_item(json: annotated, debug: debug)
        raise CreatorError, Uc3DmpId::MSG_DMP_NO_DMP_ID if resp.nil?

        # _post_process(json: annotated)
        annotated
      end

      private

      def _preregister_dmp_id(json:, debug: false)
        # Use the specified DMP ID if the provenance has permission
        existing = json.fetch('dmp_id', {})
        id = existing['identifier'].gsub(%r{https?://}, Helper::PK_DMP_PREFIX) if existing.is_a?(Hash) &&
                                                                                  !existing['identifier'].nil?
        return id if existing['type'].downcase == 'doi' && !id.nil? && !Finder.exists?(p_key: id)

        dmp_id = ''
        counter = 0
        while dmp_id == '' && counter <= 10
          prefix = "#{ENV['DMP_ID_SHOULDER']}#{SecureRandom.hex(2).upcase}#{SecureRandom.hex(2)}"
          dmp_id = prefix unless Finder.exists?(p_key: prefix)
          counter += 1
        end
        # Something went wrong and it was unable to identify a unique id
        raise CreatorError, MSG_UNABLE_TO_MINT if counter >= 10

        puts "Uc3DmpId::Creator._pregister_dmp_id - registering DMP ID: #{dmp_id}" if debug
        url = ENV['DMP_ID_BASE_URL'].gsub(%r{https?://}, '')
        "#{Helper::PK_DMP_PREFIX}#{url.end_with?('/') ? url : "#{url}/"}#{dmp_id}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Once the DMP has been created, we need to register it's DMP ID and download any
      # PDF if applicable
      # -------------------------------------------------------------------------
      def _post_process(json:)
        return false unless json.is_a?(Hash)

        # We are creating, so this is always true
        json['dmphub_updater_is_provenance'] = true
        # Publish the change to the EventBridge
        # EventPublisher.publish(source: 'DmpCreator', dmp: json, debug: @debug)
        true
      end
    end
  end
end
