# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'

module Functions
  # The handler for PUT /dmps/{dmp_id+}
  class PutDmp
    SOURCE = 'PUT /dmps/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      params = event.fetch('pathParameters', {})
      dmp_id = params['dmp_id']
      body = event.fetch('body', '')

      # Debug, output the incoming Event and Context
      debug = SsmReader.debug_mode?
      pp event if debug
      pp context if debug

      _set_env

      # Fail if the DMP ID specified was not valid
      p_key = KeyHelper.path_parameter_to_pk(param: dmp_id)
      return Responder.respond(status: 400, errors: Messages::MSG_DMP_INVALID_DMP_ID, event: event) if p_key.nil?

      # Fail if the JSON is invalid
      validation = Validator.validate(mode: 'amend', json: body)
      return Responder.respond(status: 400, errors: validation[:errors], event: event) unless validation[:valid]

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      table = SsmReader.get_ssm_value(key: SsmReader::TABLE_NAME)

      # Fail if the Provenance could not be loaded
      p_finder = ProvenanceFinder.new(client: client, table_name: table, debug_mode: debug)
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      resp = p_finder.provenance_from_lambda_cotext(identity: claim)
      provenance = resp[:items].first if resp[:status] == 200
      return Responder.respond(status: 403, errors: Messages::MSG_DMP_FORBIDDEN, event: event) if provenance.nil?

      # Fail if the DMP ID specified could not be found
      finder = DmpFinder.new(client: client, table_name: table, debug_mode: debug)
      resp = finder.find_dmp_by_pk(p_key: p_key)
      return Responder.respond(status: resp[:status], errors: resp[:error], event: event) unless resp[:status] == 200

      # Update the DMP
      updater = DmpUpdater.new(provenance: provenance, client: client, table_name: table, debug_mode: debug)
      resp = updater.update_dmp(p_key: p_key, json: body)
      items = resp[:items].map { |item| finder.append_versions(p_key: p_key, dmp: item) }
      Responder.respond(status: resp[:status], errors: resp[:error], items: items, event: event)
    rescue Aws::Errors::ServiceError => e
      Responder.log_error(source: SOURCE, message: e.message, details: e.backtrace)
      { statusCode: 500, body: { status: 500, errors: [Messages::MSG_SERVER_ERROR] } }
    rescue StandardError => e
      # Just do a print here (ends up in CloudWatch) in case it was the responder.rb that failed
      puts "#{SOURCE} FATAL: #{e.message}"
      puts e.backtrace
      { statusCode: 500, body: { errors: [Messages::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

    class << self
      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url)
      end
    end
  end
end
