# frozen_string_literal: true

require 'aws-sdk-s3'
require 'fileutils'
require 'uc3-sam-sceptre'

DEFAULT_REGION = 'us-west-2'

# ------------------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------------------
# This Ruby script is meant to be used to run AWS SAM CLI commands and inject parameter values derived from:
#   - SSM parameters that are prefixed with: `uc3-dmp-hub-${env}-${Key}` (e.g. `/uc3/dmp/hub/dev/HostedZoneId`)
#   - CloudFormation stack outputs that have been exported with a prefix of `${env}-${OutputName}` (e.g. `dev-DomainName`)
#
# Use the @fetchable_params and @static_params section below to define the values you want to pull from SSM
# and CF stack outputs.
#
# Expected 3 arguments: environment, run a SAM build?, run a SAM deploy?
#    For example: `ruby sam_build_deploy.rb dev true false`.
#
# NOTE: Setting the last 2 arguments to false will trigger a `sam delete`.
# ------------------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------------------

# Helper functions for calling SAM CLI
# ---------------------------------------------------------
# Fetches an SSM parameter key and returns the value
def fetch_ssm_parameter(key:)
  return nil if key.nil?

  name = key.start_with?(@ssm_key_prefix) ? key : "#{@ssm_key_prefix}#{key}"
  @ssm_client.get_parameter(name: name, with_decryption: true)&.parameter&.value
rescue Aws::SSM::Errors::ParameterNotFound => e
  puts "    unable to find value for #{key} (searched both CF stack exports and SSM)"
  nil
end

# Fetch a CloudFormation stack export
def fetch_stack_export(name:)
  return nil if name.nil?

  key = name.to_s.downcase.strip
  param = @stack_exports.select do |export|
    (export.exporting_stack_id.include?(@prefix) || export.exporting_stack_id.include?("#{@program}-#{@env}") ) &&
      export.name.downcase.strip == key
  end
  param.first&.value
end

# Search for the key in the following order: Stack exports, SSM parameters
def locate_value(key:)
  return nil if key.nil?

  val = fetch_stack_export(name: key)
  return val unless val.nil?

  fetch_ssm_parameter(key: key)
end

# Construct the AWS tags that SAM will use when building resources
def sam_tags
  tags = [
    "Program=#{@program}",
    "Service=#{@service}",
    "Subservice=#{@subservice}",
    "Environment=#{@env}",
    "CodeRepo=#{@git_repo}"
  ]
  tags << "Contact=#{@admin_email_ssm_key_suffix}" unless @admin_email_ssm_key_suffix.nil?
  tags
end

# Run a SAM deploy
def deploy_args(guided: false)
  args = [
    "--stack-name #{@stack_name}",
    "--confirm-changeset #{!@auto_confirm_changeset}",
    '--capabilities CAPABILITY_NAMED_IAM',
    '--disable-rollback false'
  ]

  # Add the CF Role if this is not development
  args << "--role-arn #{@cf_role}" if ARGV[0] != 'dev'

  # Add the S3 or ECR details depending on what we're working with
  args << "--s3-bucket #{locate_value(key: @s3_arn_key_suffix)&.gsub('arn:aws:s3:::', '')}" unless @s3_arn_key_suffix.nil?
  args << "--s3-prefix lambdas" unless @s3_arn_key_suffix.nil?
  args << "--image-repository #{locate_value(key: @ecr_uri_key_suffix)}" unless @ecr_uri_key_suffix.nil?

  args << "--guided" if guided
  args << "--tags #{sam_tags.join(' ')}"
  args << "--parameter-overrides #{build_deploy_overrides.join(' ')}"
  args.join(' ')
end

# Convert the Hash key and value into SAM deploy args
def sam_param(key:, value:)
  return '' if key.nil? || value.nil?

  "ParameterKey=#{key},ParameterValue=#{value}"
end

# Construct the SAM deploy arguments
def build_deploy_overrides
  overrides = []
  @fetchable_params.each do |hash|
    val = locate_value(key: hash[:lookup_name])
    msg = "Unable to locate value for #{hash[:lookup_name]}! Make sure it was exported from a CF Stack." if val.nil?
    next if val.nil?

    overrides << sam_param(key: hash.fetch(:template_param_name, hash[:lookup_name]), value: val)
  end
  @static_params.each { |hash| overrides << sam_param(key: hash[:template_param_name], value: hash[:value]) }
  overrides
end

# Expected 3-4 arguments: environment, run a SAM build?, run a SAM deploy?, log level (default is 'error')
#    For example: `ruby sam_build_deploy.rb dev true false`.
#
# NOTE: Setting the last 2 arguments to false will trigger a `sam delete`.
if ARGV.length >= 3
  @program = 'uc3'
  @service = 'dmp'
  @subservice = 'hub'
  @git_repo = 'https://github.com/CDLUC3/dmp-hub-cfn'
  @env = ARGV[0]

  @prefix = [@program, @service, @subservice, @env].join('-')
  @stack_name = "#{@prefix}-sam-resources"

  # The SSM and CF Export searches will be prefixed with the following
  @ssm_key_prefix = "/#{[@program, @service, @subservice, @env].join('/')}/"
  @cf_export_prefix = "#{@env}-"

  @auto_confirm_changeset = false

  @ssm_client = Aws::SSM::Client.new(region: DEFAULT_REGION)

  # Fetch the exported CF stack outputs from the global region and the default region
  @stack_exports = []
  cf_client = Aws::CloudFormation::Client.new(region: 'us-east-1')
  @stack_exports << cf_client.list_exports.exports
  cf_client = Aws::CloudFormation::Client.new(region: DEFAULT_REGION)
  @stack_exports << cf_client.list_exports.exports
  @stack_exports = @stack_exports.flatten

  if ARGV[0] != 'dev'
    @cf_roles = @stack_exports.select do |export|
      export.exporting_stack_id.include?('uc3-ops-aws-prd-iam') && export.name == 'uc3-prd-ops-cfn-service-role'
    end
    @cf_role = @cf_roles.first&.value
  end

  if ARGV[1].to_s.downcase.strip == 'true' || ARGV[2].to_s.downcase.strip == 'true'
    log_level = ARGV[3].nil? ? 'error' : ARGV[3]

    # Define the parameters required by the template.yaml
    @static_params = [
      { template_param_name: 'Env', value: ARGV[0] },
      { template_param_name: 'DebugLevel', value: log_level },
      { template_param_name: 'LogRetentionDays', value: 14 }
    ]

    @fetchable_params = [
      { template_param_name: 'CertificateArn', lookup_name: "#{@cf_export_prefix}CertificateArn" },
      { template_param_name: 'CognitoUserPoolArn', lookup_name: "#{@cf_export_prefix}CognitoUserPoolArn" },
      { template_param_name: 'DeadLetterQueueArn', lookup_name: "#{@cf_export_prefix}DeadLetterQueueArn" },
      { template_param_name: 'DomainName', lookup_name: "#{@cf_export_prefix}DomainName" },
      { template_param_name: 'DynamoTableArn', lookup_name: "#{@cf_export_prefix}DynamoTableArn" },
      { template_param_name: 'DynamoTableName', lookup_name: "#{@cf_export_prefix}DynamoTableName" },
      { template_param_name: 'EventBusArn', lookup_name: "#{@cf_export_prefix}EventBusArn" },
      { template_param_name: 'HostedZoneId', lookup_name: "#{@cf_export_prefix}HostedZoneId" },
      { template_param_name: 'S3PrivateBucketId', lookup_name: "#{@cf_export_prefix}S3PrivateBucketId" },
      { template_param_name: 'S3CloudFrontBucketArn', lookup_name: "#{@cf_export_prefix}S3CloudFrontBucketArn" },
      { template_param_name: 'SnsEmailTopicArn', lookup_name: "#{@cf_export_prefix}SnsTopicEmailArn" }
    ]
  end

  if ARGV[1].to_s.downcase.strip == 'true'
    # Run the SAM build
    puts 'Building SAM artifacts ...'
    system("sam build --parameter-overrides #{build_deploy_overrides}")
  end

  # If we want to deploy the API and Lambda resources
  if ARGV[2].to_s.downcase.strip == 'true'
    # The lookup keys for the Admin email and an S3 bucket or ECR that the SAM resources should be deployed to
    @s3_arn_key_suffix = "#{@cf_export_prefix}S3PrivateBucketArn"
    @ecr_uri_key_suffix = nil
    @admin_email_ssm_key_suffix = 'AdminEmail'
    puts "Deploying SAM artifacts and building CloudFormation stack #{@stack_name} ..."
    system("sam deploy #{deploy_args(guided: false)}")
  end

  if ARGV[1].to_s.downcase.strip == 'false' && ARGV[2].to_s.downcase.strip == 'false'
    args = ["--stack-name #{@stack_name}"]

    # Add the CF Role if this is not development
    # args << "--role-arn #{@cf_role}" if ARGV[0] != 'dev'

    puts "Deleting SAM CloudFormation stack #{@stack_name} ..."
    system("sam delete #{args.join(' ')}")
  end
else
  p 'Expected 3 arguments: environment, run a SAM build?, run a SAM deploy?'
  p '    For example: `ruby sam_build_deploy.rb dev true false`.'
  p ''
  p 'NOTE: Setting the last 2 arguments to false will trigger a `sam delete`.'
end
