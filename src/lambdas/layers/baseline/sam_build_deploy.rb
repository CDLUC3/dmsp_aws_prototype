# frozen_string_literal: true

# ------------------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------------------
# This Ruby script is meant to be used to run AWS SAM CLI commands and inject parameter values derived from:
#   - SSM parameters that are prefixed with: `uc3-dmp-hub-${env}-${Key}` (e.g. `/uc3/dmp/hub/dev/HostedZoneId`)
#   - CloudFormation stack outputs that have been exported with a prefix of `${env}-${OutputName}` (e.g. `dev-DomainName`)
#
# Customizing:
#   Please see the section below that contains 'UPDATE ME!' to define the parameters unique to your Lambda function.
#   For most scenarios, you should not need to change anything else in this file
#
# Usage:
#   Expected 3-4 arguments: environment, run a SAM build?, run a SAM deploy? and the logging level
#   For example: `ruby sam_build_deploy.rb dev true false debug`.
#
#   NOTE: Setting the build and deploy boolean arguments to `false` will trigger a `sam delete`.
# ------------------------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------------------------

require 'aws-sdk-s3'
require 'fileutils'
require 'uc3-sam-sceptre'

if ARGV.length >= 3
  DEFAULT_REGION = 'us-west-2'

  @env = ARGV[0]
  @run_build = ARGV[1].to_s.downcase.strip == 'true'
  @run_deploy = ARGV[2].to_s.downcase.strip == 'true'
  @log_level = ARGV.length >= 4 ? ARGV[3]&.downcase&.strip : 'error'

  # =======================================================================================================
  # =======================================================================================================
  #
  # UPDATE ME!
  #
  # IF YOU ARE COPY/PASTING this script into a new folder you will likely only need to update this section
  @function_name = 'BaselineLambdaLayer'

  # If :use_docker is true, your AWS SAM template must have a `Metadata` section and the dir should have a
  # Dockerfile. This will cause SAM to build and deploy the image to our ECR. If set to false, the directory
  # will be zipped and placed in our S3 bucket
  @use_docker = false

  # Define any Paramaters here that are required by your template and are not available in SSM or as
  # CloudFormation stack outputs
  @native_params = { Env: @env }

  # List the names of all other parameters whose values should be available as exported CloudFormation stack
  # outputs. The env prefix will be appended to each name your provide.
  #    For example if the name of the parameter is 'DomainName' this script will look for 'dev-DomainName'
  @cf_params = %w[]

  # List the names of all other parameters whose values should be available as SSM parameters. The name must
  # match the final part of the SSM key name. This script will append the prefix automatically.
  #    For example if the parameter is 'DomainName' this script will look for '/uc3/dmp/hub/dev/DomainName'
  @ssm_params = %w[]

  # List any Lambdas that use this Layer so they are auto rebuilt/deployed or deleted after this Lambda is
  @dependent_lambdas = [
    '../../harvesters/harvestable_dmps',
    '../../harvesters/datacite',
    # '../../harvesters/ror',
    '../../indexers/dmp' #,
    # '../../indexers/typeahead',
    # '../../../sam'
  ]
  #
  # DON'T FORGET TO: Add an entry to the Sceptre config for lambda-iam.yaml and lambda-vpc.yaml for this Layer!
  # ----------------
  #
  # =======================================================================================================
  # =======================================================================================================

  # Fetches all of the CloudFormation Stack Outputs (they must have been 'Exported')
  def fetch_cf_stack_exports
    exports = []
    cf_client = Aws::CloudFormation::Client.new(region: 'us-east-1')
    exports << cf_client.list_exports.exports
    cf_client = Aws::CloudFormation::Client.new(region: DEFAULT_REGION)
    exports << cf_client.list_exports.exports
    exports.flatten
  end

  # Fetch the stack output values for each item in the array
  def cf_params_to_sam
    @cf_params.map do |key|
      next if key.nil?

      val = fetch_cf_output(name: key)
      puts "Unable to find an 'exported' CloudFormation stack output for '#{key}'!" if val.nil?
      next if val.nil?

      sam_param(key: key, value: val)
    end
  end

  # Search the stack outputs for the name
  def fetch_cf_output(name:)
    vals = @stack_exports.select do |exp|
      (exp.exporting_stack_id.include?(@prefix) || exp.exporting_stack_id.include?("#{@program}-#{@env}") ) &&
      exp.name.downcase.strip == "#{@env}-#{name&.downcase&.strip}"
    end
    vals&.first&.value
  end

  # Fetch the stack output values for each item in the array
  def ssm_params_to_sam
    @ssm_params.map do |key|
      next if key.nil?

      val = fetch_ssm_value(name: key.start_with?(@ssm_prefix) ? key : "#{@ssm_prefix}#{key}")
      puts "Unable to find an SSM parameter for '#{key}'!" if val.nil?
      next if val.nil?

      sam_param(key: key, value: val)
    rescue Aws::SSM::Errors::ParameterNotFound => e
      puts "    unable to find value for #{key} (searched both CF stack exports and SSM)"
      next
    end
  end

  # Fetch the SSM parameter
  def fetch_ssm_value(name:)
    val = @ssm_client.get_parameter(name: name, with_decryption: true)&.parameter&.value
  end

  # Convert the Hash key and value into SAM deploy args
  def sam_param(key:, value:)
    return '' if key.nil? || value.nil?

    "ParameterKey=#{key},ParameterValue=#{value}"
  end

  # Build the SAM tags
  def sam_tags
    tags = ["Program=#{@program}", "Service=#{@service}", "Subservice=#{@subservice}", "Environment=#{@env}",
            "CodeRepo=#{@git_repo}"]
    tags << "Contact=#{@admin_email}" unless @admin_email.nil?
    tags.join(' ')
  end

  @program = 'uc3'
  @service = 'dmp'
  @subservice = 'hub'
  @git_repo = 'https://github.com/CDLUC3/dmsp_aws_prototype'
  @auto_confirm_changeset = false
  @prefix = [@program, @service, @subservice, @env].join('-')
  @ssm_prefix = "/#{[@program, @service, @subservice, @env].join('/')}/"
  @stack_name = "#{@prefix}-#{@function_name}"

  @stack_exports = fetch_cf_stack_exports

  if @run_build || @run_deploy
    @ssm_client = Aws::SSM::Client.new(region: DEFAULT_REGION)

    # Define the parameters the template needs
    overrides = [
      @native_params.keys.map { |key| sam_param(key: key, value: @native_params[key]) },
      cf_params_to_sam,
      ssm_params_to_sam
    ].flatten.compact.uniq

    # If we are running the build
    if @run_build
      # Run the SAM build
      puts 'Building SAM artifacts ...'
      system("sam build --parameter-overrides #{overrides.join(' ')}")
    end

    # If we want to deploy the API and Lambda resources
    if @run_deploy
      @admin_email = fetch_ssm_value(name: "#{@ssm_prefix}AdminEmail")

      args = [
        "--stack-name #{@stack_name}",
        "--confirm-changeset #{!@auto_confirm_changeset}",
        '--capabilities CAPABILITY_NAMED_IAM',
        '--disable-rollback false',
        "--tags #{sam_tags}"
      ]

      # Add the CF Role if this is not development
      if @env != 'dev'
        cf_roles = @stack_exports.select do |export|
          export.exporting_stack_id.include?('uc3-ops-aws-prd-iam') && export.name == 'uc3-prd-ops-cfn-service-role'
        end
        args << "--role-arn #{cf_roles.first&.value}"
      end

      # Add the S3 or ECR details depending on what we're working with
      if @use_docker
        args << "--image-repository #{fetch_cf_output(name: 'EcrRepositoryUri')}"
      else
        s3_arn = fetch_cf_output(name: 'S3PrivateBucketArn')
        args << "--s3-bucket #{s3_arn&.gsub('arn:aws:s3:::', '')}"
        args << "--s3-prefix lambdas"
      end

      args << "--parameter-overrides #{overrides.join(' ')}"

      # Uncomment to debug
      # pp args

      puts "Deploying SAM artifacts and building CloudFormation stack #{@stack_name} ..."
      system("sam deploy #{args.join(' ')}")
    end

    # Build/Deploy all of the related Lambda functions
    @dependent_lambdas.each do |lambda_dir|
      system("cd #{lambda_dir} && ruby sam_build_deploy.rb #{@env} #{@run_build} #{@run_deploy} #{@log_level}")
    end

  else
    args = ["--stack-name #{@stack_name}"]

    @dependent_lambdas.each do |lambda_dir|
      system("cd #{lambda_dir} && ruby sam_build_deploy.rb #{@env} false false")
    end

    puts "Deleting SAM CloudFormation stack #{@stack_name} ..."
    system("sam delete #{args.join(' ')}")
  end
else
  p 'Expected 4 arguments: environment, run a SAM build?, run a SAM deploy? and the logging level'
  p '    For example: `ruby sam_build_deploy.rb dev true false debug`.'
  p ''
  p 'NOTE: Setting the last 2 arguments to false will trigger a `sam delete`.'
end
