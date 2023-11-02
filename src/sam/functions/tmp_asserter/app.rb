# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-id'
require 'uc3-dmp-provenance'

module Functions
  # The handler for PUT /tmp/{dmp_id+}
  class TmpAsserter
    SOURCE = 'PUT /tmp/{dmp_id+}'

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def self.process(event:, context:)
      # Setup the Logger
      log_level = ENV.fetch('LOG_LEVEL', 'error')
      req_id = context.aws_request_id if context.is_a?(LambdaContext)
      logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

      # Get the params
      params = event.fetch('pathParameters', {})
      dmp_id = params['dmp_id']
      json = JSON.parse(event.fetch('body', '{"works":2}'))

      # Fail if the DMP ID is not a valid DMP ID
      p_key = Uc3DmpId::Helper.path_parameter_to_pk(param: dmp_id)
      p_key = Uc3DmpId::Helper.append_pk_prefix(p_key:) unless p_key.nil?
      s_key = Uc3DmpId::Helper::DMP_LATEST_VERSION
      return _respond(status: 400, errors: Uc3DmpId::Helper::MSG_DMP_INVALID_DMP_ID, event:) if p_key.nil?

      _set_env(logger:)

      # Fail if the Provenance could not be loaded
      claim = event.fetch('requestContext', {}).fetch('authorizer', {})['claims']
      provenance = Uc3DmpProvenance::Finder.from_lambda_cotext(identity: claim, logger:)
      return _respond(status: 403, errors: Uc3DmpId::Helper::MSG_DMP_FORBIDDEN, event:) if provenance.nil?

      # Fetch the DMP ID
      logger.debug(message: "Searching for PK: #{p_key}, SK: #{s_key}") if logger.respond_to?(:debug)
      client = Uc3DmpDynamo::Client.new
      dmp = Uc3DmpId::Finder.by_pk(p_key:, s_key:, cleanse: false, client:, logger:)

      work_count = json.fetch('works', '2').to_s.strip.to_i
      grant_ror = json.fetch('grant', 'https://ror.org/01bj3aw27').to_s.downcase.strip

      mods = { publications: [], datasets: [], softwares: [] }
      work_count.times do
        prov = %w[Crossref Datacite Openaire].sample
        score = [3, 6, 11, 100].sample
        confidence = case score
                     when 100
                       'Absolute'
                     when 6
                       'Medium'
                     when 11
                       'High'
                     else
                       'Low'
                     end
        notes = case score
                when 100
                    ['the grant ID matched']
                when 6
                  ['repositories matched', 'titles are similar', 'contributor names and affiliations matched']
                when 11
                  ['the funding opportunity number matched', 'contributor ORCIDs matched', 'titles are similar']
                else
                  ['keywords match', 'titles are similar', 'contributor names and affiliations matched']
                end

        work_type = %w[publications datasets softwares].sample
        mods[:"#{work_type}"] << {
          id: "https://example.com/#{SecureRandom.hex(8)}",
          provenance: prov,
          timstamp: Time.now.iso8601,
          confidence: confidence,
          score: score,
          notes: notes,
          status: 'pending',
          dmproadmap_related_identifier: _add_work
        }
      end
      logger.debug(message: "Tmp Asserter update to PK: #{p_key}", details: { requested: json, mods: })

      # Update the DMP ID
      augmenter = JSON.parse({ PK: 'AUGMENTERS#datacite', name: 'Datacite' }.to_json)
      run_id = "#{Time.now.utc.strftime('%Y-%m-%d')}_#{SecureRandom.hex(8)}"
      aug = Uc3DmpId::Augmenter.new(run_id:, augmenter:, dmp:, logger:)
      resp = aug.add_modifications(works: JSON.parse(mods.to_json))
      _respond(status: 200, items: ["#{resp} modifications added to the DMP."], event:)
    rescue Uc3DmpId::UpdaterError => e
      _respond(status: 400, errors: [Uc3DmpId::Helper::MSG_DMP_NO_DMP_ID, e.message], event:)
    rescue StandardError => e
      logger.error(message: e.message, details: e.backtrace)
      { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    class << self
      # Set the Cognito User Pool Id and DyanmoDB Table name for the downstream Uc3DmpCognito and Uc3DmpDynamo
      def _set_env(logger:)
        ENV['COGNITO_USER_POOL_ID'] = ENV['COGNITO_USER_POOL_ID']&.split('/')&.last
        ENV['DMP_ID_SHOULDER'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_shoulder, logger:)
        ENV['DMP_ID_BASE_URL'] = Uc3DmpApiCore::SsmReader.get_ssm_value(key: :dmp_id_base_url, logger:)
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {}, params: {})
        Uc3DmpApiCore::Responder.respond(
          status:, items:, errors:, event:,
          page: params['page'], per_page: params['per_page']
        )
      end

      def _add_grant(funder:)
        return nil if funder.nil?

        {
          name: funder[:name],
          funder_id: {
            type: 'ror',
            identifier: funder[:ror]
          },
          funding_status: 'granted',
          grant_id: {
            identifier: "https://doi.org/11.1111/#{SecureRandom.hex(6)}",
            type: 'doi'
          }
        }
      end

      def _add_work
        {
          work_type: %w[dataset article data_paper software].sample,
          descriptor: %w[references cites is_part_of].sample,
          type: 'doi',
          identifier: "https://dx.doi.org/77.6666/#{SecureRandom.hex(4)}"
        }
      end
    end
  end
end
