# frozen_string_literal: true

require 'aws-sdk-dynamodb'
require 'aws-sdk-ssm'

module Functions
  # The handler for: GET /dmps/{dmp_id+}
  class AddDmp
    SOURCE = 'GET /dmps/{dmp_id+}'

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

      p "EVENT: #{event}"

      payload = event.fetch('payload', {})
      p "DMP: #{payload}"

      client = Aws::DynamoDB::Client.new(region: ENV.fetch('AWS_REGION', nil))
      p "CLIENT: #{client.inspect}"

      table = Aws::SSM::Client.new.get_parameter(name: '/uc3/dmp/hub/dev/DynamoTableName',
                                                 with_decryption: true)
      p "TABLE: #{table}"

      dmp_id = "10.55555/22.#{SecureRandom.hex(6)}"
      p "NEW DMP ID: #{dmp_id}"

      payload['PK'] = "DMP##{dmp_id}"
      payload['SK'] = "VERSION#latest"

      response = client.put_item(
        {
          table_name: table,
          item: payload,
          return_consumed_capacity: 'TOTAL'
        }
      )

      p "RESPONSE: #{response.inspect}"
      return { data: [], errorType: 400, errorMessage: 'Bad request' } if response[:item].nil? ||
                                                                          response[:item].empty?

      dmp = response.items.map { |item| JSON.parse({ dmp: item.item }.to_json) }.compact.uniq.first
      p "DMP: #{dmp.inspect}"

      # Convert it to GraphQL
      {
        data: {
          id: dmp['PK'].gsub('DMP#', ''),
          title: dmp['title'],
          description: dmp['description'],
          created: dmp['created'],
          updated: dmp['updated'],
          ethical_issues_exist: dmp['ethical_issues_exist'],
          contact: {
            name: dmp['contact']['name'],
            email: dmp['contact']['mbox']
            id: dmp['contact']['contact_id']['identifier']
          }
        }
      }
    end
  end
end
