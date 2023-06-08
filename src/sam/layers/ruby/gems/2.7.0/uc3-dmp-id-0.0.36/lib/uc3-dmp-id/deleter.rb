# frozen_string_literal: true

module Uc3DmpId
  class DeleterError < StandardError; end

  # Utility to Tombstone DMP ID'a
  class Deleter
    class << self
      # Delete/Tombstone a record in the table
      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # -------------------------------------------------------------------------
      def tombstone(provenance:, p_key:, debug: false)
        raise DeleterError, MSG_DMP_INVALID_DMP_ID unless p_key.is_a?(String) && !p_key.strip.empty?

        # Fail if the provenance is not defined
        raise DeleterError, MSG_DMP_FORBIDDEN unless provenance.is_a?(Hash) && !provenance['PK'].nil?

        # Fetch the latest version of the DMP ID by it's PK
        client = Uc3DmpDynamo::Client.new(debug: debug)
        dmp = Finder.by_pk(p_key: p_key, client: client, debug: debug)
        raise DeleterError, MSG_DMP_NOT_FOUND unless dmp.is_a?(Hash) && !dmp['dmp'].nil?

        # Only allow this if the provenance is the owner of the DMP!
        raise DeleterError, MSG_DMP_FORBIDDEN if dmp['dmp']['dmphub_provenance_id'] != provenance['PK']
        # Make sure they're not trying to update a historical copy of the DMP
        raise DeleterError, MSG_DMP_NO_HISTORICALS if dmp['dmp']['SK'] != Helper::DMP_LATEST_VERSION

        # Annotate the DMP ID
        dmp['dmp']['SK'] = Helper::DMP_TOMBSTONE_VERSION
        dmp['dmp']['dmphub_tombstoned_at'] = Time.now.iso8601
        dmp['dmp']['title'] = "OBSOLETE: #{dmp['title']}"
        puts "Tombstoning DMP #{p_key}" if debug

        # Create the Tombstone version
        resp = client.put_item(json: dmp, debug: debug)
        raise DeleterError, MSG_DMP_NO_TOMBSTONE if resp.nil?

        # Delete the Latest version
        resp = client.delete_item(p_key: p_key, s_key: Helper::SK_DMP_PREFIX, debug: debug)

# TODO: We should do a check here to see if it was successful!
puts resp.inspect

        # Notify EZID about the removal
        _post_process(json: dmp, debug: debug)
        dmp
      rescue Aws::Errors::ServiceError => e
        Responder.log_error(source: source, message: e.message,
                            details: ([@provenance] << e.backtrace).flatten)
        { status: 500, error: Messages::MSG_SERVER_ERROR }
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      private

      # Once the DMP has been tombstoned, we need to notify EZID
      # -------------------------------------------------------------------------
      def _post_process(json:, debug: false)
        return false unless json.is_a?(Hash)

        # Indicate whether or not the updater is the provenance system
        json['dmphub_updater_is_provenance'] = true
        # Publish the change to the EventBridge
        publisher = Uc3DmpEventBridge::Publisher.new
        publisher.publish(source: 'DmpDeleter', dmp: json, debug: debug)
        true
      end
    end
  end
end
