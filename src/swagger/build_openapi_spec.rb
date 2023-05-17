require 'fileutils'
require 'json'
require 'aws-sdk-resourcegroups'
require 'aws-sdk-ssm'
require 'aws-sdk-s3'

DEFAULT_REGION = 'us-west-2'
GLOBAL_REGION = 'us-east-1'

if ARGV.length == 2
  # Setup AWS SDK clients
  resource_groups = Aws::ResourceGroups::Client.new(region: DEFAULT_REGION)
  ssm = Aws::SSM::Client.new(region: GLOBAL_REGION)

  # Get the CloudFront Distribution Id
  ssm_key = "/uc3/dmp/hub/#{ARGV[0]}/CloudFrontDistroId"
  cf_distro = ssm.get_parameter(name: ssm_key, with_decryption: true)&.parameter&.value

  # Fetch the S3 buckets tagged for our service
  resources = resource_groups.search_resources({
    resource_query: {
      type: 'TAG_FILTERS_1_0',
      query: {
        ResourceTypeFilters: ['AWS::S3::Bucket'],
        TagFilters: [
          { Key: 'Service', Values: %w[dmp] },
          { Key: 'Subservice', Values: %w[hub] },
          { Key: 'Environment', Values: [ARGV[0]] },
        ]
      }.to_json
    }
  })
  s3_bucket = resources&.resource_identifiers.map(&:resource_arn)
                                             .select { |arn| arn.include?('s3cloudfrontbucket') }
                                             .first
                                             .gsub('arn:aws:s3:::', '')

  if cf_distro.nil? || s3_bucket.nil?
    p "    unable to find the s3 bucket and/or cloudfront distribution!"
    2
  else
    swagger_dir = "swagger-ui-#{ARGV[1]}"

    # Install the Swagger UI if necessary
    unless Dir.exists?(swagger_dir)
      p "Installing Swagger UI v#{ARGV[1]} ..."
      sleep(2)
      `wget \"https://github.com/swagger-api/swagger-ui/archive/v#{ARGV[1]}.tar.gz\"`
      `tar -zxvf v#{ARGV[1]}.tar.gz`
      File.delete("v#{ARGV[1]}.tar.gz")
    end

    # Convert the DMP Json Schema to OpenApi format
    p 'Converting JSON schema in ../sam/gems/uc3-dmp-id/lib/schemas/author.json to OpenApi format ...'
    conversion_output = `yarn run json-schema-to-openapi-schema convert ../sam/gems/uc3-dmp-id/lib/schemas/author.json`
    conversion_output = conversion_output.split(/\n/)[2]
    begin
      dmp_component = JSON.parse(conversion_output)
    rescue JSON::ParserError
      p "    failure when trying to parse the JSON from the json-schema-to-openapi-schema converter."
      3
    end
    begin
      openapi_spec = JSON.parse(File.read('v0-openapi-template.json'))
    rescue JSON::ParserError
      p "    failure when trying to parse the OpenApi spec v0-openapi-template.json."
      4
    end

    if dmp_component.nil? ||
       openapi_spec.nil? ||
       openapi_spec.fetch('components', {}).fetch('schemas', {})['Dmp'].nil?
      p "    unable to process the JSON schema and/or the OpenApi spec!"
      5
    else
      # Splice the DMP schema definition into the OpenApi spec
      p "Preparing files for Swagger UI ..."
      openapi_spec['components']['schemas']['Dmp'] = dmp_component

      # Add the files to the Swagger UI distribution
      FileUtils.mkdir("#{swagger_dir}/dist/docs") unless Dir.exists?("#{swagger_dir}/dist/docs")

      FileUtils.cp('v0-api-docs.json', "#{swagger_dir}/dist/docs-list.json")
      FileUtils.cp_r('assets/', "#{swagger_dir}/dist/")
      FileUtils.cp('default_index.html', "#{swagger_dir}/dist/index.html")

      output = File.open("#{swagger_dir}/dist/docs/v0-openapi-spec.json", 'w+')
      output.write(openapi_spec.to_json)
      output.close

      # Push Swagger UI distro to S3 using CLI because SDK doesn't have 'sync'
      p "Putting updated Swagger UI files onto S3 #{s3_bucket} ..."
      system("aws s3 sync #{swagger_dir}/dist s3://#{s3_bucket}/api-docs")

      # Invalidate the CloudFront cache so that our changed Swagger UI takes effect
      p "Invalidating the CloudFront cache so our changes are picked up ..."
      system("aws cloudfront create-invalidation --distribution-id #{cf_distro} --paths /api-docs/* --region #{GLOBAL_REGION}")
    end
    0
  end
else
  p "    expected 2 args! The environment, the swagger ui version"
  1
end
