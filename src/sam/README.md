# dmp-hub-sam
DMPHub Lambdas orchestrated by AWS SAM

<img src="aws-sam-architecture.png?raw=true">

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
