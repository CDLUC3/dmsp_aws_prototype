# frozen_string_literal: true

require 'spec_helper'

# Load the Mock Data Store that will monkey patch the Uc3DmpDyanmo::Client and Uc3DmpEventBridge::Publisher
require_relative '../support/mock_data_store'
require_relative '../support/mock_event_bus'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Full Integration Tests' do
  # TODO: Add in checks for EventBridge messages
  # let!(:publisher) { mock_uc3_dmp_event_bridge }

  let!(:owner) { JSON.parse({ PK: 'PROVENANCE#foo', SK: 'PROFILE', name: 'foo' }.to_json) }
  let!(:external_updater) { JSON.parse({ PK: 'PROVENANCE#bar', SK: 'PROFILE', name: 'bar' }.to_json) }

  let!(:p_key) { "#{Uc3DmpId::Helper::PK_DMP_PREFIX}#{mock_dmp_id}" }
  let!(:provenance_identifier) { JSON.parse({ type: 'url', identifier: 'https://some.site.edu/dmps/12345' }.to_json) }

  let!(:dynamo_client) { Uc3DmpDynamo::Client.new }

  before do
    ENV['DOMAIN'] = 'https://test.org'
    ENV['DMP_ID_SHOULDER'] = '11.22222/33'
    ENV['DMP_ID_BASE_URL'] = 'https://doi.org'
    ENV['EVENT_BUS_NAME'] = 'test-bus'

    allow(Uc3DmpDynamo::Client).to receive(:new).and_return(dynamo_client)
    mock_uc3_dmp_event_bridge
  end

  # rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength
  it 'succeeds in all the things' do
    original_dmp = mocked_dmp(pkey: p_key)
    original_dmp['dmp']['dmp_id'] = provenance_identifier

    # Test seeding a DMP ID
    owner['seedingWithLiveDmpIds'] = true
    original_dmp['dmp']['dmproadmap_external_system_identifier'] = mock_dmp_id
    new_dmp = Uc3DmpId::Creator.create(provenance: owner, json: original_dmp)
    expect(dynamo_client.data_store.length).to be(1)
    new_dmp_tests(original: original_dmp, new_dmp:, dynamo_rec: dynamo_client.data_store.last, seeding: true)

    # Register a new DMP ID
    owner['seedingWithLiveDmpIds'] = false
    new_dmp = Uc3DmpId::Creator.create(provenance: owner, json: original_dmp)
    expect(dynamo_client.data_store.length).to be(2)
    new_dmp_tests(original: original_dmp, new_dmp:, dynamo_rec: dynamo_client.data_store.last)
    pk = Uc3DmpId::Helper.dmp_id_to_pk(json: new_dmp['dmp']['dmp_id'])

    # pp dynamo_client.data_store.map { |rec| { PK: rec['PK'], SK: rec['SK'], modified: rec['modified'] } }

    # Attaches the narrative PDF document
    url = 'http://test.edu/docs/123.pdf'
    expect(Uc3DmpId::Updater.attach_narrative(provenance: owner, p_key: pk, url:)).to be(true)
    expect(dynamo_client.data_store.length).to be(2)
    test_attachment(url:, prior_dmp: new_dmp, dmp: Uc3DmpId::Finder.by_pk(p_key: pk),
                    dynamo_rec: dynamo_client.data_store.last)

    # Update the DMP ID (as the system of provenance)
    modified = JSON.parse({ dmp: new_dmp['dmp'].dup }.to_json)
    modified['dmp']['description'] = 'Testing update of DMP ID.'
    expect(modified['dmp']['description']).not_to eql(new_dmp['dmp']['description'])
    updated_dmp = Uc3DmpId::Updater.update(provenance: owner, p_key: pk, json: modified)
    expect(dynamo_client.data_store.length).to be(2)
    expect(updated_dmp['dmp']['description']).to eql('Testing update of DMP ID.')
    expect(updated_dmp['dmp']['dmphub_versions'].nil?).to be(true)
    expect(updated_dmp['dmp']['dmphub_modifications'].nil?).to be(true)
    updated_dmp_id_tests(prior_dmp: new_dmp, dmp: updated_dmp, dynamo_rec: dynamo_client.data_store.last)

    # Force the DMP ID modified date to something in the past so we can test versioning
    new_tstamp = (Time.parse(updated_dmp['dmp']['modified']) - 720_000).utc.iso8601
    dynamo_client.change_timestamps(p_key: pk, tstamp: new_tstamp)
    updated_dmp['dmp']['created'] = new_tstamp
    updated_dmp['dmp']['modified'] = new_tstamp

    # Versions the DMP ID as if the update happens several days later
    modified_again = JSON.parse({ dmp: updated_dmp['dmp'].dup }.to_json)
    modified_again['dmp']['description'] = 'Testing update of DMP ID again to create a new version.'
    expect(modified_again['dmp']['description']).not_to eql(updated_dmp['dmp']['description'])
    updated_again = Uc3DmpId::Updater.update(provenance: owner, p_key: pk, json: modified_again)
    expect(dynamo_client.data_store.length).to be(3)
    expect(updated_again['dmp']['description']).to eql('Testing update of DMP ID again to create a new version.')
    # There are no :dmphub_modifications at this point
    expect(updated_again['dmp']['dmphub_versions'].length).to be(2)
    expect(updated_again['dmp']['dmphub_modifications'].nil?).to be(true)
    updated_dmp_id_tests(prior_dmp: updated_dmp, dmp: updated_again, dynamo_rec: dynamo_client.data_store.last,
                         expect_versioned: true)

    # Update the DMP ID (as an external system) wait a few seconds so the timestamps are different
    sleep(1)
    external_mod = JSON.parse({ dmp: updated_again['dmp'].dup }.to_json)
    # Test a change to a field that an external system cannot make!
    external_mod['dmp']['description'] = 'This change should be illegal!'
    expect(external_mod['dmp']['description']).not_to eql(updated_again['dmp']['description'])
    # Test a discovered :grant_id
    external_mod['dmp']['project'].first['funding'].first['grant_id'] = JSON.parse({
      type: 'url', identifier: 'http:grants.example.org/my/test'
    }.to_json)
    # Test the discovery of new related works
    if external_mod['dmp']['dmproadmap_related_identifiers'].nil?
      external_mod['dmp']['dmproadmap_related_identifiers'] =
        []
    end
    external_mod['dmp']['dmproadmap_related_identifiers'] << JSON.parse({
      work_type: 'article', descriptor: 'is_cited_by', type: 'doi', identifier: 'http://doi.org/55.66666/some.journal/123'
    }.to_json)
    external_mod['dmp']['dmproadmap_related_identifiers'] << JSON.parse({
      work_type: 'dataset', descriptor: 'references', type: 'doi', identifier: 'http://dx.doi.org/33.4444/ABC555.34'
    }.to_json)
    external_update = Uc3DmpId::Updater.update(provenance: external_updater, p_key: pk, json: external_mod)
    expect(dynamo_client.data_store.length).to be(4)
    external_mod_tests(prior_dmp: updated_again, dmp: external_update, dynamo_rec: dynamo_client.data_store.last)

    # Retains the :dmphub_modifications after another update from the system of provenance
    sleep(1)
    final_mod = JSON.parse({ dmp: external_update['dmp'].dup }.to_json)
    final_mod['dmp']['description'] = 'Final update test'
    expect(final_mod['dmp']['description']).not_to eql(external_update['dmp']['description'])
    last_update = Uc3DmpId::Updater.update(provenance: owner, p_key: pk, json: final_mod)
    expect(dynamo_client.data_store.length).to be(4)
    expect(last_update['dmp']['description']).to eql('Final update test')
    expect(last_update['dmp']['dmphub_versions'].length).to be(3)
    expect(last_update['dmp']['dmphub_modifications']).to eql(external_update['dmp']['dmphub_modifications'])
    updated_dmp_id_tests(prior_dmp: external_update, dmp: last_update, dynamo_rec: dynamo_client.data_store.last,
                         expect_versioned: false)

    # Retains the :dmphub_modifications after another external system finds mods
    # Update the DMP ID (as an external system) wait a few seconds so the timestamps are different
    sleep(1)
    external_mod2 = JSON.parse({ dmp: last_update['dmp'].dup }.to_json)
    # Test a change to a field that an external system cannot make!
    external_mod2['dmp']['description'] = 'This change should be illegal!'
    expect(external_mod2['dmp']['description']).not_to eql(last_update['dmp']['description'])
    # Test the discovery of new related works
    new_id = JSON.parse({ work_type: 'software', descriptor: 'references', type: 'url',
                          identifier: 'http://github.com/test/project123' }.to_json)
    external_mod2['dmp']['dmproadmap_related_identifiers'] << new_id

    other_updater = JSON.parse({ PK: 'PROVENANCE#baz', SK: 'PROFILE', name: 'baz' }.to_json)

    external_update2 = Uc3DmpId::Updater.update(provenance: other_updater, p_key: pk, json: external_mod2)
    expect(dynamo_client.data_store.length).to be(5)
    # Was unable to change the description
    expect(external_update2['dmp']['description']).to eql(last_update['dmp']['description'])
    # Retained all of the old :dmphub_modifications
    last_update['dmp']['dmphub_modifications'].each do |mod|
      expect(external_update2['dmp']['dmphub_modifications'].include?(mod)).to be(true), "Expected #{mod}"
    end
    # Added the new :related_identifiers to the :dmphub_modifications
    new_one = external_update2['dmp']['dmphub_modifications'].select do |mod|
      mod.fetch('dmproadmap_related_identifiers', []).include?(new_id)
    end
    expect(new_one.nil?).to be(false)

    # Tombstones the DMP ID
    sleep(1)
    tombstoned = Uc3DmpId::Deleter.tombstone(provenance: owner, p_key: pk)
    # pp dynamo_client.data_store.map { |rec| { PK: rec['PK'], SK: rec['SK'], modified: rec['modified'] } }

    expect(dynamo_client.data_store.length).to be(5)
    dynamo_rec = dynamo_client.data_store.last

    expect(tombstoned['dmp']['title']).to eql("OBSOLETE: #{external_update2['dmp']['title']}")
    expect(tombstoned['dmp']['modified'] >= external_update2['dmp']['modified']).to be(true)

    expect(dynamo_client.get_item(key: { PK: pk, SK: Uc3DmpId::Helper::DMP_LATEST_VERSION })).to be_nil
    expect(dynamo_rec['SK']).to eql(Uc3DmpId::Helper::DMP_TOMBSTONE_VERSION)
    expect(dynamo_rec['dmphub_tombstoned_at'] >= external_update2['dmp']['modified']).to be(true)
  end
  # rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def new_dmp_tests(original:, new_dmp:, dynamo_rec:, seeding: false)
    # Validate the record that was returned to the caller
    expect(new_dmp['dmp'].nil?).to be(false)
    # Validate the structure of the DMP ID (unless we are seeding because then it may not have our EZID shoulder)
    validate_dmp_id(dmp_id: new_dmp['dmp']['dmp_id']) unless seeding
    # The generated DMP ID should NOT match the original (unless we are seeding)
    expect(new_dmp['dmp']['dmp_id']['identifier'] != original['dmp']['dmp_id']['identifier']) unless seeding
    expect(new_dmp['dmp']['dmp_id']['identifier'] == original['dmp']['dmp_id']['identifier']) if seeding
    # There should be no :dmphub_versions since this is a new record
    expect(new_dmp['dmp']['dmphub_versions'].nil?).to be(true)
    # There are no :dmphub_modifications at this point
    expect(new_dmp['dmp']['dmphub_modifications'].nil?).to be(true)
    # Replaced the incoming :created and :modified timestamps
    expect(new_dmp['dmp']['created'] > original['dmp']['created']).to be(true)
    expect(new_dmp['dmp']['modified'] > original['dmp']['modified']).to be(true)

    # Validate the record sent to the Dynamo data store
    expect(dynamo_rec['dmp'].nil?).to be(true)
    # Validate the structure of the DMP ID (unless we are seeding because then it may not have our EZID shoulder)
    validate_dmp_id(dmp_id: dynamo_rec['dmp_id']) unless seeding
    # Validate that the :PK matches the :dmp_id
    pk = Uc3DmpId::Helper.dmp_id_to_pk(json: dynamo_rec['dmp_id'])
    expect(dynamo_rec['PK']).to eql(pk)
    expect(dynamo_rec['SK']).to eql(Uc3DmpId::Helper::DMP_LATEST_VERSION)
    expect(dynamo_rec['dmphub_provenance_id']).to eql(owner['PK'])
    expected = original.fetch('dmp', {}).fetch('dmp_id', {})['identifier']&.gsub(%r{https?://}, "#{owner['name']}#")
    expect(dynamo_rec['dmphub_provenance_identifier']).to eql(expected)
    mod_date = Time.parse(dynamo_rec['modified'])
    expect(dynamo_rec['dmphub_modification_day']).to eql(mod_date.strftime('%Y-%m-%d'))
    expected = original.fetch('dmp', {}).fetch('contact', {}).fetch('contact_id', {})['identifier']
    expect(dynamo_rec['dmphub_owner_id']).to eql(expected)
    expected = original.fetch('dmp', {}).fetch('contact', {}).fetch('dmproadmap_affiliation', {})
                       .fetch('affiliation_id', {})['identifier']
    expect(dynamo_rec['dmphub_owner_org']).to eql(expected)
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  # rubocop:disable Metrics/AbcSize
  def test_attachment(url:, prior_dmp:, dmp:, dynamo_rec:)
    expected = JSON.parse({
      work_type: 'output_management_plan', descriptor: 'is_metadata_for', type: 'url', identifier: url
    }.to_json)
    expect(dmp['dmp']['dmproadmap_related_identifiers'].any? { |id| id == expected }).to be(true)
    # Expect the timestamps NOT to change
    expect(dmp['dmp']['created']).to eql(prior_dmp['dmp']['created'])
    expect(dmp['dmp']['modified']).to eql(prior_dmp['dmp']['modified'])
    expect(dmp['dmp']['dmphub_versions'].nil?).to be(true)
    expect(dmp['dmp']['dmphub_modifications'].nil?).to be(true)
    expected = Time.parse(prior_dmp['dmp']['modified']).strftime('%Y-%m-%d')
    expect(dynamo_rec['dmphub_modification_day']).to eql(expected)
  end
  # rubocop:enable Metrics/AbcSize

  # Validate the JSON that was returned
  # rubocop:disable Metrics/AbcSize
  def updated_dmp_id_tests(prior_dmp:, dmp:, dynamo_rec:, expect_versioned: false)
    # The returned record should be wrapped in a top level :dmp
    expect(dmp['dmp'].nil?).to be(false)
    # Validate the structure of the DMP ID
    validate_dmp_id(dmp_id: dmp['dmp']['dmp_id'])
    # Replaced the incoming :created and :modified timestamps
    expect(dmp['dmp']['created'] == prior_dmp['dmp']['created']).to be(true)

    if expect_versioned
      expected = Time.parse(dmp['dmp']['modified']).strftime('%Y-%m-%d')
      expect(dmp['dmp']['modified'] > prior_dmp['dmp']['modified']).to be(true)
      expect(dynamo_rec['dmphub_modification_day']).to eql(expected)
      expect(dmp['dmp']['dmphub_versions'].first['timestamp']).to eql(prior_dmp['dmp']['modified'])
      expect(dmp['dmp']['dmphub_versions'].last['timestamp']).to eql(dmp['dmp']['modified'])
      first_url = dmp['dmp']['dmphub_versions'].first['url']
      expect(first_url.end_with?("?version=#{prior_dmp['dmp']['modified']}")).to be(true)
      expect(dmp['dmp']['dmphub_versions'].last['url'].include?('?version=')).to be(false)
    else
      same_hour = (Time.now.utc - Time.parse(dmp['dmp']['modified'])).round <= 3600
      expected = Time.parse(prior_dmp['dmp']['modified']).strftime('%Y-%m-%d')
      expect(dmp['dmp']['modified'] >= prior_dmp['dmp']['modified'] && same_hour).to be(true)
      expect(dynamo_rec['dmphub_modification_day']).to eql(expected)
    end
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize
  def external_mod_tests(prior_dmp:, dmp:, dynamo_rec:)
    # Expect a new version to have been created
    expect(dmp['dmp']['dmphub_versions'].length).to be(3)
    expect(dmp['dmp']['modified'] > prior_dmp['dmp']['modified']).to be(true)
    expected = Time.parse(dmp['dmp']['modified']).strftime('%Y-%m-%d')
    expect(dynamo_rec['dmphub_modification_day']).to eql(expected)
    expect(dmp['dmp']['dmphub_versions'].first['timestamp'] < prior_dmp['dmp']['modified']).to be(true)
    expect(dmp['dmp']['dmphub_versions'][1]['timestamp']).to eql(prior_dmp['dmp']['modified'])
    expect(dmp['dmp']['dmphub_versions'].last['timestamp']).to eql(dmp['dmp']['modified'])
    expect(dmp['dmp']['dmphub_versions'].first['url'].end_with?("?version=#{prior_dmp['dmp']['created']}")).to be(true)
    expect(dmp['dmp']['dmphub_versions'].last['url'].include?('?version=')).to be(false)

    # Expect the description to not have been changed because it is not allowed!
    # We currently only allow :grant_id and :dmproadmap_related_identifiers to be changed by external systems
    expect(dmp['dmp']['description']).to eql(prior_dmp['dmp']['description'])
    # Expect the original :grant id and original :dmproadmap_related_identifiers to be unchanged
    expected = prior_dmp['dmp']['project'].first['funding'].first['grant_id']
    expect(dmp['dmp']['project'].first['funding'].first['grant_id']).to eql(expected)
    expect(dmp['dmp']['dmproadmap_related_identifiers']).to eql(prior_dmp['dmp']['dmproadmap_related_identifiers'])
    # Expect the changes to have been added to the :dmphub_modifications Array
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize
  def validate_dmp_id(dmp_id:)
    pk = dmp_id['identifier']
    expect(pk.start_with?(ENV.fetch('DMP_ID_BASE_URL', nil))).to be(true)
    suffix = pk.gsub(ENV.fetch('DMP_ID_BASE_URL', nil), '')
    expect(suffix =~ Uc3DmpId::Helper::DOI_REGEX).to be(1)
    expect(suffix.start_with?("/#{ENV.fetch('DMP_ID_SHOULDER', nil)}")).to be(true)
  end
  # rubocop:enable Metrics/AbcSize

  def mocked_dmp(pkey:)
    record = mock_dmp
    scrubbable_keys = record['dmp'].keys.select { |key| %w[PK SK].include?(key) || key.start_with?('dmphub_') }
    scrubbable_keys.each { |key| record['dmp'].delete(key) }
    record['dmp']['dmp_id'] = Uc3DmpId::Helper.pk_to_dmp_id(p_key: pkey)
    record
  end
end
# rubocop:enable RSpec/DescribeClass
