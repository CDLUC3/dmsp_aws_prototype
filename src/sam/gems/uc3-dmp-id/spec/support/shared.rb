# frozen_string_literal: true

require 'ostruct'
require 'securerandom'

require 'uc3-dmp-citation'
require 'uc3-dmp-dynamo'
require 'uc3-dmp-event-bridge'

# Mock S3 Resources
Uc3DmpCloudwatchLogger = Struct.new('Uc3DmpCloudwatchLogger', :new, :debug, :info, :warn, :error)
Uc3DmpDynamoClient = Struct.new('Uc3DmpDynamoClient', :get_item, :put_item, :delete_item, :query)
Uc3DmpEventBridgePublisher = Struct.new('Uc3DmpEventBridgePublisher', :publish)

def mock_dmp_id
  domain = ENV.fetch('DMP_ID_BASE_URL', 'doi.org').gsub(%r{https?://}, '')
  "#{domain}/#{rand(10...99)}.#{rand(10_000...99_999)}/#{SecureRandom.hex(6)}"
end

def mock_dmp(minimal: false)
  JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/#{minimal ? 'minimal' : 'complete'}.json"))
end

def mock_logger(success: true)
  lggr = Uc3DmpCloudwatchLogger.new
  allow(lggr).to receive_messages(debug: success, info: success, warn: success, error: success)
  allow(Uc3DmpCloudwatch::Logger).to receive(:new).and_return(lggr)
  lggr
end

def mock_uc3_dmp_dynamo(dmp: mock_dmp, success: true)
  client = Uc3DmpDynamoClient.new
  ret = success ? dmp : nil
  allow(client).to receive_messages(get_item: ret, put_item: ret, delete_item: ret,
                                    query: (success ? [dmp] : nil), pk_exists?: success)
  allow(Uc3DmpDynamo::Client).to receive(:new).and_return(client)
  client
end

def mock_uc3_dmp_event_bridge(success: true)
  publisher = Uc3DmpEventBridgePublisher.new
  allow(publisher).to receive(:publish).and_return(success)

  allow(Uc3DmpEventBridge::Publisher).to receive(:new).and_return(publisher)
  publisher
end

# Helper to compare 2 hashes
# rubocop:disable Metrics/MethodLength, Metrics/AbcSize
# rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
def assert_dmps_match(obj_a: {}, obj_b: {}, debug: false)
  pass = obj_a.instance_of?(obj_b.class)

  if debug
    puts 'Debug from spec/support/shared.rb - assert_dmps_match'
    pp obj_a
    p '-----------'
    pp obj_b
  end

  if pass
    case obj_a.class.name
    when 'Array'
      return false unless obj_a.length == obj_b.length

      obj_a.each { |entry| pass = false unless obj_b.include?(entry) }
    when 'Hash'
      return false unless obj_a.keys.sort { |a, b| a <=> b } == obj_b.keys.sort { |a, b| a <=> b }

      obj_a.each_pair do |key, value|
        # rubocop:disable Metrics/BlockNesting
        if %w[Array Hash].include?(value.class.name)
          pass = assert_dmps_match(obj_a: value, obj_b: obj_b.nil? ? nil : obj_b[key.to_s])
        else
          # puts "Hash item #{key} not a sub Hash/Array #{value} == #{obj_b.nil? ? nil : obj_b[key.to_s]}"
          pass = false unless value == obj_b.nil? ? nil : obj_b[key.to_s]
        end
        # rubocop:enable Metrics/BlockNesting
      end
    else
      # puts "#{obj_a} == #{obj_b}"
      pass = false unless obj_a == obj_b
    end
  end
  pass
end
# rubocop:enable Metrics/MethodLength, Metrics/AbcSize
# rubocop:enable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
