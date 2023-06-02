# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-rds'

module Functions
  # The handler for: PUT /dmps/{dmp_id+}
  class PutWip
    SOURCE = 'PUT /wips/{wip_id+}'

    MSG_INVALID_WIP = 'Unable to save the work in progress (WIP) record. Expected a JSON object like /
                       \'{ "dmp": { "title": "My example DMP", "dmphub_owner": { "mbox": "you@exmzple.com" } } }\''
    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def self.process(event:, context:)
      # Sample pure Lambda function

      # Parameters
      # ----------
      # event: Hash, required
      #     API Gateway Lambda Proxy Input Format
      #     Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format

      # context: object, required
      #     Lambda Context runtime methods and attributes
      #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html

      # Returns
      # ------
      # API Gateway Lambda Proxy Output Format: dict
      #     'statusCode' and 'body' are required
      #     # api-gateway-simple-proxy-for-lambda-output-format
      #     Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html

      # begin
      #   response = HTTParty.get('http://checkip.amazonaws.com/')
      # rescue HTTParty::Error => error
      #   puts error.inspect
      #   raise error
      # end
      params = event.fetch('pathParameters', {})
      principal = event.fetch('requestContext', {}).fetch('authorizer', {})
      return _respond(status: 401, errors: [Uc3DmpRds::MSG_MISSING_USER], event: event) if principal.nil? ||
                                                                                           principal['mbox'].nil?

      wip_id = params.fetch('wip_id', '').to_s.strip
      body = event.fetch('body', '{}').to_s.strip
      continue = !body.empty? && !wip_id.empty?
      json = JSON.parse(body) if continue
      # The minimum WIP requires a :title
      continue = !json.fetch('dmp', {})['title'].nil? if continue
      return _respond(status: 400, errors: [MSG_INVALID_WIP], event: event) unless continue

      # Debug, output the incoming Event and Context
      debug = Uc3DmpApiCore::SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      # Connect to the DB
      connected = _establish_connection
      return _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event: event) unless connected

      # Find the original record
      original = _select(wip_id: wip_id).first
      return _respond(status: 404, errors: [Uc3DmpApiCore::MSG_NOT_FOUND], event: event) if original.nil?

      # Verify that the user has authority to perform the update
      verified = _verify_ownership(owner: principal, wip_id: wip_id, wip: json, original: original)
      return _respond(status: 403, errors: [Uc3DmpApiCore::MSG_FORBIDDEN], event: event) if verified.nil?
      # Update the WIP
      _update(owner: principal, wip_id: wip_id, wip: verified)
      _respond(status: 200, items: [verified], event: event)
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the Uc3DmpApiCore::Responder that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    private

    class << self
      # Update the WIP
      def _update(owner:, wip_id:, wip:)
        tstamp = Time.now.strftime('%Y-%m-%dT%H:%M:%S')
        sql_str = <<~SQL.squish
          UPDATE wips
          SET metadata = :metadata, updated_at = :tstamp
          WHERE identifier = :identifier AND (metadata->>\'$.dmp.dmphub_owner_id\' = :owner_id)
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, identifier: wip_id, metadata: wip.to_json,
                                         tstamp: tstamp, owner_id: owner['id'])
        wip
      end

      # Fetch the updated WIP
      def _select(wip_id:)
        sql_str = <<~SQL.squish
          SELECT * FROM wips WHERE identifier = :wip_id LIMIT 1
        SQL
        Uc3DmpRds::Adapter.execute_query(sql: sql_str, wip_id: wip_id)
      end

      # Verify that the owner of the update matches the owner of the original record and add the
      # dmphub_owner_id and dmphub_wip_id to the payload if necessary
      def _verify_ownership(owner:, wip_id:, wip:, original:)
        return nil if owner.nil? || wip_id.nil? || !wip.is_a?(Hash) || wip['dmp'].nil? || original.nil?

        metadata = JSON.parse(original.fetch('metadata', {}))

        # Attach the wip_id and owner_id to the update if it doesn't have them
        wip['dmp']['dmphub_wip_id'] = { type: 'other', identifier: wip_id } if wip['dmp']['dmphub_wip_id'].nil?
        wip['dmp']['dmphub_owner_id'] = owner['id'] if wip['dmp']['dmphub_owner_id'].nil?

        # Ensure that the metadata is for the correct WIP and that the owner is the same as the principal!
        verified = metadata['dmp'].fetch('dmphub_wip_id', {})['identifier'].to_s.strip == wip_id &&
                   metadata['dmp']['dmphub_owner_id'].to_s.strip == owner['id'].to_s.strip
        verified ? wip : nil
      end

      # make a connection to the RDS DB
      def _establish_connection
        # Fetch the DB credentials from SSM parameter store
        username = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_username)
        password = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :rds_password)
        Uc3DmpRds::Adapter.connect(username: username, password: password)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {})
        Uc3DmpApiCore::Responder.respond(status: status, items: items, errors: errors, event: event)
      end
    end
  end
end
