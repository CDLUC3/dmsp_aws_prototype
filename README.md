# DMPHub
         _                 _           _
      __| |   _  _   ___  | |__  _   _| |_
     / _` |  / \/ \ |  _ \| `_ \| | | | '_ \
    | (_| | / /\/\ \| | ) | | | | |_| | |_) |
     \__,_|/_/    \_| '__/|_| |_|_____|_'__/
                    |_|

This repository manages both the application logic and the infrastructure for the DMPHub metadata repository.
It works in conjunction with the [dmp-hub-ui repository](https://github.com/CDLUC3/dmp-hub-ui) which contains the source code for the React UI.

It is designed specifically for the Amazon Web Services (AWS) ecosystem. Please note that you must have an AWS account and that building the system will create resources in your account that may incur charges!

<img src="docs/architecture.png?raw=true">

You can run `./resources-ls.sh` to see what AWS resources have been created by these CloudFormation templates.

## Directory layout

This repository uses the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) to manage the AWS API Gateway, Lambda functions and other related resources (e.g. IAM policies). It uses [Sceptre](https://github.com/Sceptre/sceptre) to manage the remaining resources (e.g. CloudFront, DynamoDB, etc.) via [AWS CloudFormation](https://aws.amazon.com/cloudformation/).

The entire build process is managed by Sceptre. Sceptre has a hook that will build the SAM application once the resources it depends on (e.g. DynamoDb Table, Cognito, etc.) have been created.

Directory structure:
```
     resources-ls.sh                         # A shell script that will show all existing AWS resources for this project
     |
     seed_dynamo.sh                          # A shell script that will seed provenance records in the DynamoDB Table (auto-run by dynamo.yaml config)
     |
     config
     |  |
     |   ----- [env]                         # Sceptre configs by Environment (each config corresponds to a template)
     |            |
     |             ----- global              # Resources that will be created in the us-east-1 region
     |            |
     |             ----- regional            # Resources that will be created in the us-east-1 region
     |
     docs                                    # Diagrams and documentation
     |
     src
     |  |
     |   ----- sam                           # The SAM managed code
     |           |
     |            ----- functions            # The lambda functions
     |           |
     |            ----- layers               # The lambda layers
     |           |
     |            ----- spec                 # Tests for the functions and layers
     |           |
     |            ----- samconfig.toml       # The SAM configuration file 
     |           |
     |            ----- template.yaml        # The SAM Cloud Formation template
     |           |
     |            ----- sam_build_deploy.sh  # A shell script that can be used to build and deploy your SAM resources (auto-run by dynamo.yaml config)
     |
     templates                               # The Cloud Formation templates (each template corresponds to a config)
```

## Installation and Setup

This repository uses [Sceptre](https://docs.sceptre-project.org/3.2.0/) to orchestrate the creation, update and deletion of [AWS Cloud Formation](https://aws.amazon.com/cloudformation/) stacks. See below for notes about Sceptre if this is your first time using this technology.

For instructions on installing and setting up the system, please refer to [our installation wiki](https://github.com/CDLUC3/dmp-hub-cfn/wiki/installation-and-setup)

## Testing

Sceptre allows you to test your templates and config prior to building the CloudFormation stacks. You can do this by running `sceptre validate config/[env]/[dir]/[config_file].yaml`.

Note that Sceptre always shows you the change set and asks you to confirm before it will make any changes to your AWS environment.

To test the Lambda functions and Lambda Layer, you can run `./src/sam/test.sh`. This will build the Lambda Layer (The Lambda functions require the layer code to be zipped up) and then execute Rubocop checks followed by the RSpec tests for both the layer and the functions.

## Database

For details about the structure of DynamoDB items and DMP versioning logic, please refer to [our database documentation wiki page](https://github.com/CDLUC3/dmp-hub-cfn/wiki/database)


## Notes about SAM

You can update and deploy the AWS SAM managed Lambdas and the API Gateway independently. To do that please use the supplied shell script which will make AWS CLI calls to fetch the ARNs for various resources that were created/managed by Sceptre and CloudFormation.

To run the script you must supply 3 arguments. For example: `./src/sam/sam_build_deploy.sh dev dmphub-dev.cdlib.org true` 
- The 1st arg is the environment you wish to use. The environment must match a defined environment in the `src/sam/samconfig.toml` file.
- The 2nd arg is the domain name. The API Gateway will automatically append the `api.` subdomain.
- The 3rd arg is a boolean that indicates whether or not the LambdaLayer should be compiled. Set this to false if you are not updating the layer to speed things up. 

Note that the there is an `after_create` Sceptre hook on the `config/[env]/regional/dynamo.yaml` that will execute this shell script.

## Notes about Sceptre

AWS Resource names are auto-constructed by Sceptre using the "${directory-name}-${stack-name}-${resource-id}" format.
For example a sceptre project directory like this:
```
# Project directory layout:
# -------------------------------
my-project
    |
     ---- config
    |      |
    |       ------ config.yaml
    |      |
    |       ------ dev
    |               |
    |                ----- s3.yaml
    |
     ---- templates
             |
              ----- s3.yaml (containing a resource called ExampleBucket)


# config/config.yaml contents:
# -------------------------------
project_code: my-cf-bucket
region: us-west-2


# config/dev/s3.yaml contents:
# -------------------------------
template:
  path: s3.yaml
  type: file

# templates/s3.yaml contents:
# -------------------------------
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  ExampleBucket:
    Type: AWS::S3::Bucket
```
Would result in a BucketName of `my-project-dev-s3-ExampleBucket-3487y23t8` which is derived from:
```
 my-project- dev-s3- ExampleBucket - 3487y23t8
     ^          ^         ^            ^
     |          |         |            |
     |          |         |             ------- Sceptre generated random id to ensure uniqueness
     |          |         |
     |          |          --------- Resource name from template templates/s3.yaml in this case
     |          |
     |           ------------ config file directory + name config/dev/s3.yaml in this case
     |
      -------------- derived from the project's root directory name
```

Sceptre will place a copy of the compiled/aggregated CloudFormation template into the S3 bucket defined in the stack's root `config/config.yaml` which is `my-cf-bucket` in the example above. You can also inspect the stack in the AWs console to see the resources created, outputs defined, along with the logs.

### Creating new stacks

Create a new env specific config directory: `mkdir config/[env] && touch config/[env]/config.yaml`

Create a new Cloud Formation (CF) template: `touch templates/[resource-type].yaml config/dev/[resource-type].yaml`
