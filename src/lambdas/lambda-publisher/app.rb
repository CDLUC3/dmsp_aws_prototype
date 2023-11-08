# frozen_string_literal: true

require 'aws-sdk-lambda'
require 'aws-sdk-s3'

module Functions
  # Lambda function that is invoked by SNS and communicates with EZID to register/update DMP IDs
  class LambdaPublisher
    SOURCE = 'Lambda Publication Function'

    # Parameters
    # ----------
    # event: Hash, required
    #     EventBridge Event input (the bits we care about):
    #       {
    #         "CodePipeline.job": {
    #           "data": {
    #             "actionConfiguration": {
    #               "configuration": {
    #                 "FunctionName": "my-function",
    #                 "UserParameters": "{\"layer_id\": \"arn:aws:lambda:us-west-2:123456789:layer:my-layer:2\"}"}},
    #                 "inputArtifacts": [{
    #                   "name": "dev-EventBridge-SourceOutput",
    #                   "revision": "revision_id",
    #                   "location": {
    #                     "type": "S3",
    #                     "s3Location": {
    #                       "bucketName": "my-bucket",
    #                       "objectKey": "path/to/revision.zip"
    #                     }
    #                   }
    #                 }]
    #
    # context: object, required
    #     Lambda Context runtime methods and attributes
    #     Context doc: https://docs.aws.amazon.com/lambda/latest/dg/ruby-context.html
    class << self
      def process(event:, context:)
        event.fetch('Records', []).each do |record|
          config = record.fetch('s3', {})
          puts "Record info: #{config}"
          # Make sure we are only paying attention to the S3 events we want!
          next unless config['configurationId'] == 'PublishLambdas'

          s3_client = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))
          lambda_client = Aws::Lambda::Client.new(region: ENV.fetch('AWS_REGION', 'us-west-2'))

          s3_config = _extract_s3_info(client: s3_client, config:)
          puts "S3 info: #{s3_config}"
          next if s3_config.nil? || s3_config[:env].nil? || s3_config[:name_suffix].nil?

          if s3_config[:key].include?('/layers/')
            resp = _publish_layer_version(client: lambda_client, s3_config:)
            resp.nil? ? 'Unable to deploy LambdaLayer!' : 'New revision has been deployed.'
          else
            resp = _publish_function_version(client: lambda_client, s3_config:)
            resp.nil? ? 'Unable to deploy LambdaFunction!' : 'New revision has been deployed.'
          end
        end
        { statusCode: 200, message: "Ok" }
      rescue StandardError => e
        puts "#{SOURCE} ERROR: #{e.message}"
        puts e.backtrace
        { statusCode: 500, message: "Ok" }
      end

      private

      # Extract all of the relevant S3 info from the incoming event and fetch the revision from S3
      def _extract_s3_info(client:, config:)
        config = {
          bucket: config.fetch('bucket', {})['name'],
          key: config.fetch('object', {})['key'],
          version_id: config.fetch('object', {})['versionId']
        }
        obj_tags = client.get_object_tagging(config).tag_set
        config[:env] = obj_tags.select { |set| set.key == 'Env' }.first&.value
        config[:name_suffix] = obj_tags.select { |set| set.key == 'NameSuffix' }.first&.value
        config
      end

      # Find the appropriate Lambda Layer and deploy the latest revision
      def _publish_layer_version(client:, s3_config:)
        puts "Searching for LambdaLayer that's name ends with #{s3_config[:name_suffix]}"
        layer = _find_layer(client:, s3_config:)
        return "No LambdaLayer found!" if layer.nil?

        puts "Deploying new LambdaLayer version to #{layer.layer_name}"
        client.publish_layer_version({
          layer_name: layer.layer_name,
          description: "LambdaPublisherFunction Deployment #{Time.now.iso8601}",
          content: {
            s3_bucket: s3_config[:bucket],
            s3_key: s3_config[:key],
            s3_object_version: s3_config[:version_id]
          },
        })
      end

        # Find the appropriate Lambda Function and deploy the latest revision
      def _publish_function_version(client:, s3_config:)
        puts "Searching for LambdaFunction that's name ends with #{s3_config[:name_suffix]}"
        function = _find_function(client:, s3_config:)
        return "No LambdaFunction found!" if function.nil?

        puts "Deploying new LambdaFunction version to #{function.function_name}"
        client.update_function_code({
          function_name: function.function_name,
          s3_bucket: s3_config[:bucket],
            s3_key: s3_config[:key],
            s3_object_version: s3_config[:version_id],
            publish: true
        })
      end

      # Fetches the LambdaLayer that matches the Env and NameSuffix defined in the S3 object's tags
      def _find_layer(client:, s3_config:, marker: nil)
        opts = { max_items: 50 }
        opts[:marker] = marker unless marker.nil?
        resp = client.list_layers(opts)
        layers = resp.layers.select do |layer|
          layer.layer_name.end_with?(s3_config[:name_suffix]) && layer.layer_name.include?(s3_config[:env])
        end
        return nil if layers.empty? && (resp.next_marker.nil? || resp.next_marker == marker)
        return _find_layer(client:, s3_config:, marker: resp.next_marker.to_s) if layers.empty? &&
                                                                                  !resp.next_marker.nil?

        layers.first
      end

      # Fetches the LambdaFunction that matches the Env and NameSuffix defined in the S3 object's tags
      def _find_function(client:, s3_config:, marker: nil)
        opts = { max_items: 50 }
        opts[:marker] = marker unless marker.nil?
        resp = client.list_functions(opts)
        functions = resp.functions.select do |func|
          func.function_name.end_with?(s3_config[:name_suffix]) && func.function_name.include?(s3_config[:env])
        end
        return nil if functions.empty? && (resp.next_marker.nil? || resp.next_marker == marker)
        return _find_function(client:, s3_config:, marker: resp.next_marker) if functions.empty? &&
                                                                                !resp.next_marker.nil?

        functions.first
      end

      # Send the output to the Responder
      # def _respond(code: 500, message: 'ERROR')
      #   JSON.parse({ name: SOURCE, status: code, message: message}.to_json)
      # end
    end
  end
end
