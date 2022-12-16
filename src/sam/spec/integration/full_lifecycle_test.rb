# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'httparty'

require_relative "#{Dir.getwd}/spec/support/shared.rb"
require_relative "#{Dir.getwd}/layers/ruby/lib/key_helper.rb"
require_relative "#{Dir.getwd}/layers/ruby/lib/responder.rb"
require_relative "#{Dir.getwd}/layers/ruby/lib/ssm_reader.rb"

# Full DMP lifecycle test
@hostname = ARGV.first
@env = ARGV.last
if ARGV.length != 2 || @hostname.nil? || @env.nil?
  p 'You must supply the API hostname and a 3 char environment.'
  p '    For example `ruby ./spec/integration/full_lifecycle_test.rb  https://example.com/v0 dev`'
else
  p "Using specified hostname: #{@hostname}"
  @table = Aws::SSM::Client.new.get_parameter(name: '/uc3/dmp/hub/dev/DynamoTableName',
                                              with_decryption: true).parameter.value
  @dynamodb_client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

  # Instruct the EZID Publisher, Provenance Notifier and PDF Downloader to go offline
  @ssm_client = Aws::SSM::Client.new.put_parameter(
    name: "/uc3/dmp/hub/#{ARGV.last}/EzidDebugMode", value: 'true', overwrite: true
  )

  provenances = {
    author: 'test-authoring-system',
    funder_one: 'test-funder-api-1',
    funder_two: 'test-funder-api-2',
    works_one: 'test-works-api-1',
    works_two: 'test-works-api-2',
    curator: 'test-curator@example.com'
  }

  # Basic HTTParty options (Headers are defined in spec/support/shared.rb)
  opts = {
    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
    follow_redirects: true,
    limit: 6
  }
  @funding = []
  @works = []
  @versions = []

  # rubocop:disable Metrics/AbcSize
  def process_response(response:)
    @title = response['title']
    @funding = response.fetch('project', []).first&.fetch('funding', [])
                       &.map { |f| "#{f['name']} - #{f['status']} - grant# #{f.fetch('grant_id', {})['identifier']}" }
    @works = response.fetch('dmproadmap_related_identifiers', [])
                     .map { |w| "#{w['work_type']} - #{w['descriptor']} - #{w['identifier']}" }

    vers = response.fetch('dmproadmap_related_identifiers', []).select { |id| id['descriptor'] == 'is_new_version_of' }
    unless vers.nil?
      @versions = vers.map do |v|
        "#{KeyHelper::SK_DMP_PREFIX}#{v['identifier'].split('?version=').last}"
      end
    end

    p "        DMP ID: #{@dmp_id}"
    p "        Title: #{@title}"
    p '        Funding:'
    @funding.each_with_index { |fund, idx| p "            #{idx}) #{fund}" }
    p '        Works:'
    @works.each_with_index { |work, idx| p "            #{idx}) #{work}" }
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/BlockNesting, Style/CommentedKeyword
  begin
    p 'Creating 6 test provenance records in the Dynamo DB table for testing. They will be cleaned up afterward.'
    # and a Human Curator
    provenances.each do |_key, val|
      p "   - CREATING `#{KeyHelper::PK_PROVENANCE_PREFIX}#{val}`"
      json = {
        PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}#{val}",
        SK: KeyHelper::SK_PROVENANCE_PREFIX,
        name: val
      }
      @dynamodb_client.put_item(
        { table_name: @table, item: json, return_consumed_capacity: 'TOTAL' }
      )
    end

    p 'Using JSON from `spec/support/json_mocks/complete.json` but removing DMPHub specific attributes'
    json = JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/complete.json"))
    # Remove all the DMPHub specific attributes
    json = Responder._cleanse_dmp_json(json: json)
    json['dmp']['dmp_id'] = JSON.parse({ type: 'url', identifier: 'http://example.com/test/123' }.to_json)

    # Validate the JSON
    # --------------------------------------------
    p 'Validating DMP JSON ...'
    opts[:body] = json.to_json
    uri = "#{@hostname}/dmps/validate"
    validate_response = HTTParty.post(uri, opts)
    p "    - #{validate_response['status'] == 200 ? 'SUCCESS' : 'FAIL'}!"
    pp validate_response unless validate_response['status'] == 200

    if validate_response['status'] == 200
      # Create a DMP
      # --------------------------------------------
      p "Creating DMP JSON owned by #{KeyHelper::PK_PROVENANCE_PREFIX}#{provenances[:author]} ..."
      opts[:body] = json.to_json
      uri = "#{@hostname}/dmps"
      create_response = HTTParty.post(uri, opts)
      passed = create_response['status'] == 201
      if passed
        p '    - SUCCESS'
        json = create_response['items'].first
        @dmp_id = json['dmp'].fetch('dmp_id', {})['identifier']
        process_response(response: json['dmp'])

        # Provenance system updates it's own DMP
        # --------------------------------------------
        p 'DMP author makes a change ...'
        json['dmp']['title'] = "Updated by #{provenances[:author]}"
        opts[:body] = json.to_json
        uri = "#{@hostname}/dmps/#{@dmp_id}"
        update_response = HTTParty.put(uri, opts)
        passed = update_response['status'] == 200
        if passed
          p '    - SUCCESS'
          json = update_response['items'].first
          process_response(response: json['dmp'])

          # Funder updates the DMP
          # --------------------------------------------
          p 'Funder 1 makes a change ...'
          json['dmp']['project'] = [] if json['dmp']['project'].nil?
          json['dmp']['project']['funding'] = [] if json['dmp']['project'].first['funding'].nil?
          json['dmp']['project'].first['funding'] << {
            name: provenances[:funder_one],
            status: 'granted',
            grant_id: { type: 'url', identifier: 'https://example.com/grants/ZZZZZ' }
          }
          opts[:body] = json.to_json
          uri = "#{@hostname}/dmps/#{@dmp_id}"
          update_response = HTTParty.put(uri, opts)
          passed = update_response['status'] == 200
          if passed
            p '    - SUCCESS'
            json = update_response['items'].first
            process_response(response: json['dmp'])

            # Related Id system updates the DMP
            # --------------------------------------------
            p 'Related Works 1 makes a change ...'
            json['dmp']['dmproadmap_related_identifiers'] << {
              descriptor: 'references',
              work_type: 'dataset',
              type: 'url',
              identifier: 'https://example.com/works/YYYYYY'
            }
            opts[:body] = json.to_json
            uri = "#{@hostname}/dmps/#{@dmp_id}"
            update_response = HTTParty.put(uri, opts)
            passed = update_response['status'] == 200
            if passed
              p '    - SUCCESS'
              json = update_response['items'].first
              process_response(response: json['dmp'])

              # Funder 2 updates the DMP
              # --------------------------------------------
              p 'Funder 2 makes a change ...'
              json['dmp']['project'].first['funding'] << {
                name: provenances[:funder_two],
                status: 'granted',
                grant_id: { type: 'url', identifier: 'https://example.com/grants/XXXXX' }
              }
              opts[:body] = json.to_json
              uri = "#{@hostname}/dmps/#{@dmp_id}"
              update_response = HTTParty.put(uri, opts)
              passed = update_response['status'] == 200
              if passed
                p '    - SUCCESS'
                json = update_response['items'].first
                process_response(response: json['dmp'])

                # Related Id system 2 updates the DMP
                # --------------------------------------------
                p 'Related Works 2 makes a change ...'
                json['dmp']['dmproadmap_related_identifiers'] << {
                  descriptor: 'references',
                  work_type: 'dataset',
                  type: 'url',
                  identifier: 'https://example.com/works/WWWWWW'
                }
                opts[:body] = json.to_json
                uri = "#{@hostname}/dmps/#{@dmp_id}"
                update_response = HTTParty.put(uri, opts)
                passed = update_response['status'] == 200
                if passed
                  p '    - SUCCESS'
                  json = update_response['items'].first
                  process_response(response: json['dmp'])

                  # Provenance system updates the DMP
                  # --------------------------------------------
                  p 'Authoring system makes a change again ...'
                  json['dmp']['title'] = "Updated by #{provenances[:author]} AGAIN!"
                  opts[:body] = json.to_json
                  uri = "#{@hostname}/dmps/#{@dmp_id}"
                  update_response = HTTParty.put(uri, opts)
                  passed = update_response['status'] == 200
                  if passed
                    p '    - SUCCESS'
                    json = update_response['items'].first
                    process_response(response: json['dmp'])

                    # Tombstone the DMP
                    # --------------------------------------------
                    p 'Tombstoning the DMP ...'
                    uri = "#{@hostname}/dmps/#{@dmp_id}"
                    opts.delete(:body)
                    delete_response = HTTParty.delete(uri, opts)
                    passed = delete_response['status'] == 200
                    if passed
                      p '    - SUCCESS'
                      json = delete_response['items'].first
                      process_response(response: json['dmp'])
                      @versions << KeyHelper::DMP_TOMBSTONE_VERSION

                    else # Tombstone
                      p '    - FAIL'
                      pp delete_response
                    end

                  else # Author update
                    p '    - FAIL'
                    pp update_response
                  end

                else # Works 2 update
                  p '    - FAIL'
                  pp update_response
                end

              else # Funder 2 update
                p '    - FAIL'
                pp update_response
              end

            else # Works 1 update
              p '    - FAIL'
              pp update_response
            end
          else
            p '    - FAIL'
            pp update_response
          end # Funder 1 update

        else # Author update
          p '    - FAIL'
          pp update_response
        end

      else # Creation
        p '    - FAIL'
        pp create_response
      end

      # find the DMP by PK

      # find a specific version of the DMP (make sure the right number of versions are there)

      # find the DMP by provenance id

      # find the DMP by the provenance (author, funder, and related systems)

      # Tombstone the DMP
    end
  ensure
    # Instruct the EZID Publisher, Provenance Notifier and PDF Downloader to go back online
    @ssm_client = Aws::SSM::Client.new.put_parameter(
      name: "/uc3/dmp/hub/#{ARGV.last}/EzidDebugMode", value: 'false', overwrite: true
    )

    # Delete the test provenance records
    # --------------------------------------------
    p 'Cleaning up test records from Dynamo ...'
    provenances.each do |_key, val|
      p "   - DELETING `#{KeyHelper::PK_PROVENANCE_PREFIX}#{val}`"
      @dynamodb_client.delete_item(
        {
          table_name: @table,
          key: {
            PK: "#{KeyHelper::PK_PROVENANCE_PREFIX}#{val}",
            SK: KeyHelper::SK_PROVENANCE_PREFIX
          }
        }
      )
    end

    unless @dmp_id.nil? # || @dmp_id != 'foo'
      # Delete the DMP and its versions
      # --------------------------------------------
      @versions.each do |version|
        p "    - DELETING PK: `#{KeyHelper::PK_DMP_PREFIX}#{@dmp_id}` - SK: `#{version}`"
        @dynamodb_client.delete_item(
          {
            table_name: @table,
            key: { PK: "#{KeyHelper::PK_DMP_PREFIX}#{@dmp_id}", SK: version }
          }
        )
      end

      p "    - DELETING PK: `#{KeyHelper::PK_DMP_PREFIX}#{@dmp_id}` SK: `#{KeyHelper::DMP_LATEST_VERSION}`"
      @dynamodb_client.delete_item(
        {
          table_name: @table,
          key: { PK: "#{KeyHelper::PK_DMP_PREFIX}#{@dmp_id}", SK: KeyHelper::DMP_LATEST_VERSION }
        }
      )
    end
  end
  # rubocop:enable Metrics/BlockNesting, Style/CommentedKeyword
end

p 'DONE'
