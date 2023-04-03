# AWS Serverless Application Model (SAM) resources

This directory manages the API Gateway and all Lambda functions (whether they are accessed via the API Gateway, EventBridge or another method)

The Lambda resources MUST be built on a linux machine in order for the mysql2 gem to be properly built for the Lambda environment.

To ready your Cloud9 environment you will need to:
- `sudo yum install jq` to install the JSON processor tool
- `sudo yum install mariadb-devel.x86_64` to install the mysql developer tools needed
- `rvm install 2.7.6 && rvm use 2.7.6` to install and use the correct Ruby version
- `ssh-keygen -t rsa` if you do not have a key already
- `cat ~/.ssh/id_rsa.pub` and copy the contents to GitHub so that you can read-write to this repo
- `git clone git@github.com:CDLUC3/dmp-hub-cfn.git`

Each time you login to your Cloud9 environment, you will need to establish your AWS credentials. To do that simply copy paste them into the Cloud9 terminal as you would on your developer machine.

To build the SAM resources run the sam_build.sh script and pass in the environment, domain name, and whether or not you want to build the lambda layer. For example: `./src/sam/sam_build dev dmphub-dev.cdlib.org true`



If you're already using Cloud9 for development, you can just do a normal bundle install.

Using Cloud9 is probably the easiest approach. Open your Cloud9 dev environment and do the following:
- `sudo yum install mariadb-devel.x86_64` to install the mysql developer tools needed
- `rvm install 2.7.6 && rvm use 2.7.6` or whatever the appropriate ruby version is
- `mkdir mysql2_gem && cd mysql2_gem`
- `vi Gemfile` and paste in the gemfile contents found below
- `bundle install`
- Then download the contents of mysql2_gem/ruby/2.7.0/gems/mysql2-0.5.5 to your local dev machine

## Cloud Formation

To validate the SAM Cloud Formation template: `sam validate`

To test the Lambda function in the cloud: `c`

## Building and Deploying

To build the LambdaLayer and the deployment package for AWS: `./build.sh`

To deploy the Cloud Formation stack using the config settings: `sam deploy --config-env dev`

To deploy the Cloud Formation stack and lambdas from scratch (creates new config): `sam deploy --guided`

To deploy the Cloud Formation stack and lambdas while using existing config options: `sam deploy --config-env [env]` For example 'dev'

Then answer the questions. For example:
```
Configuring SAM deploy
======================

	Looking for config file [samconfig.toml] :  Found
	Reading default arguments  :  Success

	Setting default arguments for 'sam deploy'
	=========================================
	Stack Name [sam-app]: uc3-dmp-hub-dev-lambdas
	AWS Region [us-west-2]:
	#Shows you resources changes to be deployed and require a 'Y' to initiate deploy
	Confirm changes before deploy [y/N]: y
	#SAM needs permission to be able to create roles to connect to the resources in your template
	Allow SAM CLI IAM role creation [Y/n]: y
	#Preserves the state of previously provisioned resources when an operation fails
	Disable rollback [y/N]: n
	GetDmpFunction may not have authorization defined, Is this okay? [y/N]: y
	Save arguments to configuration file [Y/n]: y
	SAM configuration file [samconfig.toml]:
	SAM configuration environment [default]: dev
```

## Development

You can have SAM deploy and then watch the environment as you make changes by running: `sam sync --watch --stack-name uc3-dmp-hub-dev-lambdas`

This will auto-deploy your changes to AWS!

## Testing

If you receive errors about missing `aws-sdk-[service]` gems, then run `bundle install --with test` to install those libraries. Lambdas already have those gems included in their environment, so there's no need for us to include them in the actual build. Running `./build.sh` builds the bundle without them.

**Lambda Tests:**
Run the following `./test.sh` to test the Lambda Layer and individual Lambda Functions. Note that this will 'build' the Lambda Layer since the functions require them to be in the ZIP format

**Integration Tests:**

You can run the following script `ruby spec/integration/full_lifecycle_test.rb` to test the live system. It will create Provenance and DMP items in the DynamoDB Table and then clean them up afterward.

It will:
- Create 5 test Provenance items (simulating 1 primary source system, 2 funder systems, and 2 related identifier systems) in the DynamoDB Table (via AWS SDK)
- Call the API to create a new DMP item in the Dynamo table for the primary source provenance
- Call the API to update the DMP item for the 1st funder provenance
- Call the API to update the DMP item for the 1st related identifier provenance
- Call the API to update the DMP item for the original source provenance
- Call the API to update the DMP item for the 2nd funder provenance
- Call the API to update the DMP item for the 2nd related identifier provenance
- Call the API to update the DMP item for the original source provenance
- Call the API to fetch the DMP by its DMP ID
- Call the API to fetch the DMP's versions
- Call the API to fetch a specific version of the DMP
- Call the API to ensure we cannot update the version of the DMP for the 1st funder provenance
- Call the API to ensure we cannot update the version of the DMP for the 1st related identifier provenance
- Call the API to ensure we cannot update the version of the DMP for the original source provenance

- Call the API to fetch the DMPs for each provenance to ensure that the DMP is included
- Call the API to tombstone the DMP
- Call the API to ensure we cannot update the tombstoned DMP item for the 1st funder provenance
- Call the API to ensure we cannot update the tombstoned DMP item for the 1st related identifier provenance
- Call the API to ensure we cannot update the tombstoned DMP item for the original source provenance
- Delete the DMP and all it's versions (via AWS SDK)
- Delete the 5 test provenances (via AWS SDK)
