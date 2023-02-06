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

## Directory layout

This repository uses the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) to manage the AWS API Gateway, Lambda functions and other related resources (e.g. IAM policies). It uses [Sceptre](https://github.com/Sceptre/sceptre) to manage the remaining resources (e.g. CloudFront, DynamoDB, etc.) via [AWS CloudFormation](https://aws.amazon.com/cloudformation/).

The entire build process is managed by Sceptre. Sceptre has a hook that will build the SAM application once the resources it depends on (e.g. DynamoDb Table, Cognito, etc.) have been created.

Directory structure:
```
     resources-ls.sh                  # Script that will show all existing AWS resources for this project
     |
     config
     |  |
     |   ----- [env]                  # Sceptre configs by Environment (each config corresponds to a template)
     |            |
     |             ----- global       # Resources that will be created in the us-east-1 region
     |            |
     |             ----- regional     # Resources that will be created in the us-east-1 region
     |
     docs                             # Diagrams and documentation
     |
     src
     |  |
     |   ----- cloudfront             # The default index.html that gets uploaded to the S3 bucket
     |  |
     |   ----- sam                    # The SAM managed code
     |           |
     |            ----- functions     # The lambda functions
     |           |
     |            ----- layers        # The lambda layers
     |           |
     |            ----- spec          # Tests for the functions and layers
     |           |
     |            ----- template.yaml # The SAM Cloud Formation template
     |
     templates                        # The Cloud Formation templates (each template corresponds to a config)
```

## Installation and Setup

This repository uses [Sceptre](https://docs.sceptre-project.org/3.2.0/) to orchestrate the creation, update and deletion of [AWS Cloud Formation](https://aws.amazon.com/cloudformation/) stacks. See below for notes about Sceptre if this is your first time using this technology.

For instructions on installing and setting up the system, please refer to [our installation wiki](https://github.com/CDLUC3/dmp-hub-cfn/wiki/installation-and-setup)

## Database

For details about the structure of DynamoDB items and DMP versioning logic, please refer to [our database documentation wiki page](https://github.com/CDLUC3/dmp-hub-cfn/wiki/database)


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
