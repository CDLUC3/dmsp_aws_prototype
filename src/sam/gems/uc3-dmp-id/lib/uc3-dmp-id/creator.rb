# frozen_string_literal: true

require 'securerandom'
require 'time'

module Uc3DmpId
  class CreatorError < StandardError; end

  class Creator
    MSG_NO_BASE_URL = 'No base URL found for DMP ID (e.g. `doi.org`)'
    MSG_NO_SHOULDER = 'No DOI shoulder found. (e.g. `10.12345/`)'
    MSG_UNABLE_TO_MINT = 'Unable to mint a unique DMP ID.'

    class << self
      def create(provenance:, json:, logger: nil)
        raise CreatorError, MSG_NO_SHOULDER if ENV['DMP_ID_SHOULDER'].nil?
        raise CreatorError, MSG_NO_BASE_URL if ENV['DMP_ID_BASE_URL'].nil?

        # Fail if the provenance is not defined
        raise DeleterError, MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil?

        # Validate the incoming JSON first
        json = Helper.parse_json(json: json)
        errs = Validator.validate(mode: 'author', json: json)
        raise CreatorError, errs.join(', ') if errs.is_a?(Array) && errs.any? && errs.first != Validator::MSG_VALID_JSON

        # Fail if the provenance or owner affiliation are not defined
        raise CreatorError, MSG_NO_PROVENANCE_OWNER if provenance.nil?

        # TODO: Swap this out with the Finder search once the Dynamo indexes are working
        # Try to find it first and Fail if found
        result = Finder.by_json(json: json, logger: logger)
        raise CreatorError, Uc3DmpId::MSG_DMP_EXISTS if result.is_a?(Hash)
        # raise CreatorError, Uc3DmpId::MSG_DMP_EXISTS unless json['PK'].nil?

        client = Uc3DmpDynamo::Client.new
        p_key = _preregister_dmp_id(client: client, provenance: provenance, json: json, logger: logger)
        raise CreatorError, MSG_UNABLE_TO_MINT if p_key.nil?

        # Add the DMPHub specific attributes and then save
        annotated = Helper.annotate_dmp_json(provenance: provenance, p_key: p_key, json: json['dmp'])
        logger.info(message: "Creating DMP ID: #{p_key}") if logger.respond_to?(:debug)

        # Set the :created and :modified timestamps
        now = Time.now.utc.iso8601
        annotated['created'] = now
        annotated['modified'] = now

        # Create the item
        resp = client.put_item(json: annotated, logger: logger)
        raise CreatorError, Uc3DmpId::MSG_DMP_NO_DMP_ID if resp.nil?

        _post_process(json: annotated, logger: logger)
        Helper.cleanse_dmp_json(json: JSON.parse({ dmp: annotated }.to_json))
      end

      private

      def _preregister_dmp_id(client:, provenance:, json:, logger: nil)
        # Use the specified DMP ID if the provenance has permission
        existing = json.fetch('dmp', {}).fetch('dmp_id', {})
        seed_id = json.fetch('dmp', {})['dmproadmap_external_system_identifier']

        # If we are seeding already registered DMP IDs from the Provenance system, then return the original DMP ID
        return seed_id.gsub(%r{https?://}, '') if existing.fetch('type', 'other') == 'url' &&
                                                  !seed_id.nil? &&
                                                  provenance.fetch('seedingWithLiveDmpIds', false).to_s.downcase == 'true'

        #Generate a new DMP ID
        dmp_id = ''
        counter = 0
        while dmp_id == '' && counter <= 10
          prefix = "#{ENV['DMP_ID_SHOULDER']}#{SecureRandom.hex(2).upcase}#{SecureRandom.hex(2)}"
          dmp_id = prefix unless Finder.exists?(client: client, p_key: prefix)
          counter += 1
        end
        # Something went wrong and it was unable to identify a unique id
        raise CreatorError, MSG_UNABLE_TO_MINT if counter >= 10

        logger.debug(message: "Preregistration DMP ID: #{dmp_id}") if logger.respond_to?(:debug)
        url = ENV['DMP_ID_BASE_URL'].gsub(%r{https?://}, '')
        "#{Helper::PK_DMP_PREFIX}#{url.end_with?('/') ? url : "#{url}/"}#{dmp_id}"
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Once the DMP has been created, we need to register it's DMP ID
      # -------------------------------------------------------------------------
      def _post_process(json:, logger: nil)
        return false unless json.is_a?(Hash)

        # We are creating, so this is always true
        json['dmphub_updater_is_provenance'] = true
        # Publish the change to the EventBridge
        publisher = Uc3DmpEventBridge::Publisher.new
        publisher.publish(source: 'DmpCreator', dmp: json, logger: logger)
        true
      end
    end
  end
end
