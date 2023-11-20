# frozen_string_literal: true

# Docs say that the LambdaLayer gems are found mounted as /opt/ruby/gems but an inspection
# of the $LOAD_PATH shows that only /opt/ruby/lib is available. So we add what we want here
# and indicate exactly which folders contain the *.rb files
my_gem_path = Dir['/opt/ruby/gems/**/lib/']
$LOAD_PATH.unshift(*my_gem_path)

require 'securerandom'
require 'time'

require 'uc3-dmp-api-core'
require 'uc3-dmp-cloudwatch'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'
require 'uc3-dmp-id'

module Functions
  # Lambda function that is invoked via an EventBridge rule that is scheduled. See the template.yaml for details
  class AugmentationScheduler
    SOURCE = 'AugmentationScheduler'

    NO_AUGMENTERS_MSG = 'No Augmenters found for related_works!'
    NO_AUGMENTER_PROFILE_MSG = 'Unable to locate the profile record for :augmenter_id.'

    class << self
      def process(event:, context:)
        # Setup the Logger
        log_level = ENV.fetch('LOG_LEVEL', 'error')
        req_id = context.aws_request_id if context.is_a?(LambdaContext)
        logger = Uc3DmpCloudwatch::Logger.new(source: SOURCE, request_id: req_id, event:, level: log_level)

        # Fetch defined augmenters `PK: AUGMENTERS`
        client = Uc3DmpDynamo::Client.new
        augs = fetch_augmenter_list(client:, logger:)
        return _respond(status: 500, errors: [NO_AUGMENTERS_MSG], event:) unless augs.is_a?(Hash)

        # Fetch any DMP IDs that need to be processed
        dmps = fetch_relevant_dmp_ids(client:, logger:)
        return _respond(status: 200, errors: [NO_DMPS], event:) unless dmps.is_a?(Array) && dmps.any?

        nbr_processed = process_dmps(client:, dmps:, augmenter_list: augs, logger:)
        _respond(status: 200, items: ["Complete"], event:)
      rescue Uc3DmpId::FinderError => e
        logger.error(message: e.message, details: e.backtrace)
        _respond(status: 500, errors: [Uc3DmpApiCore::MSG_SERVER_ERROR], event:)
      rescue StandardError => e
        logger.error(message: e.message, details: e.backtrace)
        deets = { message: e.message, augmenters: augs, dmps:}
        Uc3DmpApiCore::Notifier.notify_administrator(source: SOURCE, details: deets, event:)
        { statusCode: 500, body: { errors: [Uc3DmpApiCore::MSG_SERVER_ERROR] }.to_json }
      end

      private

      # Fetch the Augmenters record
      def fetch_augmenter_list(client:, logger:)
        client = Uc3DmpDynamo::Client.new if client.nil?
        client.get_item(key: { PK: 'AUGMENTERS', SK: 'LIST' }, logger:)
      end

      # Fetch the Augmenter's profile record
      def fetch_augmenter(client:, id:, logger:)
        client = Uc3DmpDynamo::Client.new if client.nil?
        client.get_item(key: { PK: id, SK: 'PROFILE' }, logger:)
      end

      # Fetch the list of active Augmenters
      def fetch_augmenters(client:, augmenter_list:, augmenter_type:, args:, logger:)
        return [] unless augmenter_type.is_a?(String) && augmenter_list.is_a?(Hash) &&
                         !augmenter_list[augmenter_type].nil?

        augs = augmenter_list[augmenter_type].map { |entry| fetch_augmenter(client:, id: entry['PK'], logger:) }
        augs.select { |aug| time_to_run?(now: args.fetch(:aging, {})[:now], last_run: aug['last_run']) }
      end

      # Update the last run timstamp on the Augmenter if applicable
      def update_augmenter(client:, augmenter:, tstamp:, logger:)
        augmenter['last_run'] = tstamp

        client = Uc3DmpDynamo::Client.new if client.nil?
        client.put_item(json: augmenter, logger:)
      end

      # Update the Augement list record with the latest run info
      def update_augmenters(client:, augmenter_list:, args:, counter:, logger:)
        runs = augmenter_list.fetch('runs', [])
        runs << JSON.parse({
          id: args[:run_id],
          start: args.fetch(:aging, {})[:tstamp],
          end: Time.now.iso8601,
          dmps_processed: counter
        }.to_json)
        augmenter_list['runs'] = runs

        client = Uc3DmpDynamo::Client.new if client.nil?
        client.put_item(json: augmenter_list, logger:)
      end

      # Fetch any DMPs that should be processed:
      #    - Those that were funded and have a `project: :end` within the next year
      #    - Those that were funded and have no `project: :end` BUT that were `:created` over a year ago
      #    - NOT those whose `project: :end` or `:created` dates are more than 3 years old!
      def fetch_relevant_dmp_ids(client:, logger:)
        # TODO: Update this to look at OpenSearch once we have that setup!

        #    Skip any with no :funding
        #    Skip any whose :funding_status is 'rejected'
        client = Uc3DmpDynamo::Client.new if client.nil?
        args = {
          select: 'ALL_PROJECTED_ATTRIBUTES',
          scan_filter: {
            created: { comparison_operator: '<=', attribute_value_list: [(Time.now - 86400).utc.iso8601] },
            SK: { comparison_operator: 'EQ', attribute_value_list: [Uc3DmpId::Helper::DMP_LATEST_VERSION] }
          },
          expression_attribute_names: { '#proj': 'project' },
          projection_expression: 'PK, created, #proj'
        }
        client.scan(args:, logger:)
      end

      # Determine which augmenters to invoke for the DMP
      def process_dmp(client:, publisher:, augmenters:, dmp:, args:, logger:)
        funding = dmp.fetch('project', [{}]).first&.fetch('funding', [{}])&.first
        # Skip if the funding is empty or the :funding_status is 'rejected'
        return false if funding.nil? || (funding['name'].nil? && funding.fetch('funder_id', {})['identifier'].nil?)
        return false if funding['funding_status'].to_s.downcase == 'rejected'

        logger&.info(message: "Processing #{dmp['PK']} with run_id: #{args[:run_id]}", details: dmp)

        # If the DMP has not yet been funded and we have an opportunity number
        if funding.fetch('grant_id', {})['identifier'].nil? &&
            !funding.fetch('dmproadmap_funding_opportunity_id', {})['identifier'].nil?

          trigger_augmenters(client:, publisher:, augmenter_type: :awards, augmenters:, dmp:, args:, logger:)
        else
          trigger_augmenters(client:, publisher:, augmenter_type: :related_works, augmenters:, dmp:, args:, logger:)
        end
      end

      # Trigger the relevant augmenters for the DMP
      def process_dmps(client:, augmenter_list: [], dmps: [], logger:)
        counter = 0
        args = set_run_args
        # Load the actual Augmenter records
        augmenters = {
          awards: fetch_augmenters(client:, augmenter_list:, augmenter_type: 'awards', args:, logger:),
          related_works: fetch_augmenters(client:, augmenter_list:, augmenter_type: 'related_works', args:, logger:)
        }
        publisher = Uc3DmpEventBridge::Publisher.new

        dmps.each do |dmp|
          # Skip if the DMP is not a Hash for some reason
          next unless dmp.is_a?(Hash)

          triggered = process_dmp(client:, publisher:, augmenters:, dmp:, args:, logger:)
          counter += 1 if triggered
        end
        logger&.info(message: "Triggered augmenters for #{counter} DMPs")
        update_augmenters(client:, augmenter_list:, args:, counter:, logger:)
      end

      # Determine whether the DMP meets the augmenter_type run guidelines
      def processable_dmp?(dmp:, augmenter_type:, args:, logger:)
        case augmenter_type
        when :related_works
          runnable = project_end_within_scope?(dmp:, one_year_ago: args.fetch(:aging, {})[:one_year_ago],
                                               six_months_from_now: args.fetch(:aging, {})[:six_months_from_now],
                                               three_years_from_now: args.fetch(:aging, {})[:three_years_from_now])
          logger&.debug(message: "Skipping - project not within the acceptable date range") unless runnable
          runnable
        when :awards
          # TODO: Implement this.
          # Try to determine if the project was funded
          logger&.debug(message: "Skipping- TODO: Need to search for the Award!")
          false
        else
          false
        end
      end

      # Fetch the relavant augmenters and then trigger them via EventBridge
      def trigger_augmenters(client:, publisher:, augmenter_type:, augmenters:, dmp:, args:, logger:)
        return false unless processable_dmp?(dmp:, augmenter_type:, args:, logger:)
        return false if augmenters[augmenter_type].compact.empty?

        augmenters[augmenter_type].each do |augmenter|
          logger&.debug(message: "run_id: #{args[:run_id]} -- Triggering augmenter #{augmenter['PK']}")
          triggered = trigger_augmenter(client:, publisher:, augmenter:, args:, dmp:, logger:)
          logger&.warn(message: "Unable to trigger event for #{augmenter['PK']}!") unless triggered
        end
        true
      end

      # Send an SNS notification that will kick off the augmenter for each relevant DMP ID
      def trigger_augmenter(client:, publisher:, augmenter:, args:, dmp:, logger:)
        return false if augmenter.fetch('trigger', {})['detail-type'].nil?

        # Update the Augmenter's :last_run timestamp if applicable
        set_tstamp = augmenter['last_run'] != args.fetch(:aging, {})[:tstamp]
        update_augmenter(client:, augmenter:, tstamp: args.fetch(:aging, {})[:tstamp], logger:) if set_tstamp

        # Send an SNS notification
        publisher = Uc3DmpEventBridge::Publisher.new if publisher.nil?
        event_type = augmenter['trigger']['detail-type']
        json = { run_id: args[:run_id], augmenter: augmenter['PK'], dmp_pk: dmp['PK'] }
        publisher.publish(source: SOURCE, event_type:, dmp: dmp, detail: json, logger:)
        true
      end

      # Generate a unique run id
      def generate_run_id
        prefix = Time.now.strftime('%Y-%m-%d')
        "#{prefix}_#{SecureRandom.hex(8)}"
      end

      # Generate the run arguments that will be used to generate SNS notifications and to update the
      # augmenter records with info about the run
      def set_run_args
        now = Time.now
        args = {
          run_id: generate_run_id,
          aging: {
            tstamp: now.iso8601,
            now: now.utc,
            one_year_ago: (now.utc - 3.156e+7).utc,
            six_months_from_now: (now.utc + 1.577e+7).utc,
            three_years_from_now: (now.utc + 9.467e+7).utc
          }
        }
      end

      # Check to see if it is time to process the augmenter
      def time_to_run?(now:, last_run:, frequency: 'daily')
        return true if last_run.nil? || last_run.to_s.strip == ''

        # Default increment is daily
        increment = frequency == 'weekly' ? 604800 : (frequency == 'monthly' ? 2.628e+6 : 86400)
        now = Time.now.utc unless now.is_a?(Time)
        last_run = (now - increment).utc unless last_run.is_a?(String)
        last_run = Time.parse(last_run).utc
        last_run <= (now - increment).utc
      end

      # Returns whether or not the project's end date is within scope. Meaning that we are likely to
      # see outputs (assuming we get funded project only)
      #    - Those that have a `project: :end` within the next year
      #    - Those that have no `project: :end` BUT that were `:created` over a year ago
      #    - NOT those whose `project: :end` or `:created` dates are more than 3 years old!
      def project_end_within_scope?(dmp:, one_year_ago:, six_months_from_now:, three_years_from_now:)
        project_end = Time.parse(dmp['project'].first['end']).utc unless dmp['project'].first['end'].nil?
        if project_end.nil?
          project_start = Time.parse(dmp['project'].first['start']).utc unless dmp['project'].first['start'].nil?
          project_start = Time.parse(dmp['created']).utc if project_start.nil?

          project_start >= one_year_ago && project_start <= three_years_from_now
        else
          # Return true if the project will end in the next 6 months or is within the past 3 years
          project_end <= six_months_from_now && project_end <= three_years_from_now
        end
      end

      # Send the output to the Responder
      def _respond(status:, items: [], errors: [], event: {})
        Uc3DmpApiCore::Responder.respond(status:, items:, errors:, event:)
      end
    end
  end
end
