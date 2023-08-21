# frozen_string_literal: true

require 'ostruct'
require 'securerandom'

# Mock S3 Resources
Uc3DmpDynamoClient = Struct.new('S3Client', :get_item, :put_item, :delete_item, :query)

def mock_uc3_dmp_dynamo(dmp: mock_dmp, success: true)
  client = Uc3DmpDynamoClient.new
  allow(client).to receive(:get_item).and_return(success ? dmp : nil)
  allow(client).to receive(:put_item).and_return(success ? dmp : nil)
  allow(client).to receive(:delete_item).and_return(success ? dmp : nil)
  allow(client).to receive(:query).and_return(success ? [dmp] : nil)
  allow(client).to receive(:pk_exists?).and_return(success)

  allow(Uc3DmpDynamo::Client).to receive(:new).and_return(client)
  client
end

def mock_dmp_id
  domain = ENV.fetch('DMP_ID_BASE_URL', 'doi.org').gsub(%r{https?://}, '')
  "#{domain}/#{rand(10...99)}.#{rand(10000...99999)}/#{SecureRandom.hex(6)}"
end

def mock_dmp(minimal: false)
  JSON.parse(File.read("#{Dir.pwd}/spec/support/json_mocks/#{minimal ? 'minimal' : 'complete'}.json"))
end

# Helper to compare 2 hashes
def assert_dmps_match(obj_a: {}, obj_b: {}, debug: false)
  pass = obj_a.class.name == obj_b.class.name

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
        if %w[Array, Hash].include?(value.class.name)
          pass = assert_dmps_match(obj_a: value, obj_b: obj_b.nil? ? nil : obj_b[key.to_s])
        else
          #puts "Hash item #{key} not a sub Hash/Array #{value} == #{obj_b.nil? ? nil : obj_b[key.to_s]}"
          pass = false unless value == obj_b.nil? ? nil : obj_b[key.to_s]
        end
      end
    else
      # puts "#{obj_a} == #{obj_b}"
      pass = false unless obj_a == obj_b
    end
  end
  pass
end
