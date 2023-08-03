require 'fileutils'
require 'json'
require 'aws-sdk-resourcegroups'
require 'aws-sdk-ssm'
require 'aws-sdk-s3'

DEFAULT_REGION = 'us-west-2'
GLOBAL_REGION = 'us-east-1'

if ARGV.length == 1
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

  p 'Building landing page ...'
  if cf_distro.nil? || s3_bucket.nil?
    p "    unable to find the s3 bucket and/or cloudfront distribution!"
    2
  else
    system("npm run build")
    build_dir = './build'

    # Push Swagger UI distro to S3 using CLI because SDK doesn't have 'sync'
    p "Transferring build to S3 #{s3_bucket} ..."
    system("aws s3 sync #{build_dir} s3://#{s3_bucket}/dmps")

    # Invalidate the CloudFront cache so that our changed Swagger UI takes effect
    p "Invalidating the CloudFront cache so our changes are picked up ..."
    system("aws cloudfront create-invalidation --distribution-id #{cf_distro} --paths /dmps/* --region #{GLOBAL_REGION}")
    0
  end
else
  p "    expected 1 arg! The environment (e.g. `ruby build_deploy.rb dev`)"
  1
end
