# frozen_string_literal: true

require 'ostruct'

require 'ostruct'

# Mock S3 Resources
Uc3DmpDynamoClient = Struct.new('S3Client', :get_item, :put_item, :delete_item, :query)

def mock_uc3_dmp_dynamo(success: true)
  client = Uc3DmpDynamoClient.new
  allow(client).to receive(:get_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:put_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:delete_item).and_return(success ? mock_dmp : nil)
  allow(client).to receive(:query).and_return(success ? [mock_dmp] : nil)

  allow(Uc3DmpDynamo::Client).to receive(:new).and_return(client)
end

def mock_dmp
  JSON.parse({
    dmp: {

    }
  }.to_json)
end

# Helper to compare 2 hashes
def assert_dmps_match(obj_a: {}, obj_b: {})
  pass = obj_a.class.name == obj_b.class.name

  # puts "::::: #{obj_a.class.name}"
  # pp obj_a
  # p '-----------'
  # pp obj_b

  if pass
    case obj_a.class.name
    when 'Array'
      pass = false unless obj_a.length == obj_b.length
      obj_a.each { |entry| pass = false unless obj_b.include?(entry) }
    when 'Hash'
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
