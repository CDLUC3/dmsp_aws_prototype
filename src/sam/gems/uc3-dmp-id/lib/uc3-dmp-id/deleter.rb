# frozen_string_literal: true

module Uc3DmpId
  class DeleterError < StandardError; end

  # Utility to Tombstone DMP ID'a
  class Deleter
    class << self
      # Delete/Tombstone a record in the table
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # -------------------------------------------------------------------------
      def tombstone(provenance:, p_key:, logger: nil)
        raise DeleterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        # Fail if the provenance is not defined
        raise DeleterError, MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil?

        # Fetch the latest version of the DMP ID by it's PK
        client = Uc3DmpDynamo::Client.new
        dmp = Finder.by_pk(p_key: p_key, client: client, logger: logger)
        raise DeleterError, MSG_DMP_NOT_FOUND unless dmp.is_a?(Hash) && !dmp['dmp'].nil?

        # Only allow this if the provenance is the owner of the DMP!
        raise DeleterError, MSG_DMP_FORBIDDEN if dmp['dmp']['dmphub_provenance_id'] != provenance['PK']
        # Make sure they're not trying to update a historical copy of the DMP
        raise DeleterError, MSG_DMP_NO_HISTORICALS if dmp['dmp']['SK'] != Helper::DMP_LATEST_VERSION

        # Annotate the DMP ID
        dmp['dmp']['SK'] = Helper::DMP_TOMBSTONE_VERSION
        dmp['dmp']['dmphub_tombstoned_at'] = Time.now.iso8601
        dmp['dmp']['title'] = "OBSOLETE: #{dmp['title']}"
        logger.info(message: "Tomstoning DMP ID: #{p_key}") if logger.respond_to?(:debug)

        # Create the Tombstone version
        resp = client.put_item(json: dmp, logger: logger)
        raise DeleterError, MSG_DMP_NO_TOMBSTONE if resp.nil?

        # Delete the Latest version
        resp = client.delete_item(p_key: p_key, s_key: Helper::SK_DMP_PREFIX, logger: logger)

        # TODO: We should do a check here to see if it was successful!

        # Notify EZID about the removal
        _post_process(json: dmp, logger: logger)
        # Return the tombstoned record
        Helper.cleanse_dmp_json(json: JSON.parse({ dmp: dmp }.to_json))
      rescue Aws::Errors::ServiceError => e
        logger.error(message: e.message, details: e.backtrace) unless logger.nil?
        { status: 500, error: Messages::MSG_SERVER_ERROR }
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Once the DMP has been tombstoned, we need to notify EZID
      # -------------------------------------------------------------------------
      def _post_process(json:, logger: nil)
        return false unless json.is_a?(Hash)

        # Indicate whether or not the updater is the provenance system
        json['dmphub_updater_is_provenance'] = true
        # Publish the change to the EventBridge
        publisher = Uc3DmpEventBridge::Publisher.new
        publisher.publish(source: 'DmpDeleter', dmp: json, logger: logger)
        true
      end
    end
  end
end
