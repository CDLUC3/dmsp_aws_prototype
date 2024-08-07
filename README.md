# DMSP Prototype - Infrastructure

This the Amazon Web Services (AWS) infrastructure for the DMPHub metadata repository.

Please note that you must have an AWS account and that building the system will create resources in your account that may incur charges!

<img src="docs/architecture.png?raw=true">

Once all of your AWS resources have been built, you can run `./scripts/resources-ls.sh` to see what AWS resources have been created by these CloudFormation templates.

## Directory layout

We use [Sceptre](https://github.com/Sceptre/sceptre) to manage the resources. Sceptre is a wrapper around [AWS CloudFormation](https://aws.amazon.com/cloudformation/).

```
  config
  |  |
  |   ----- [env]                         # Sceptre configs by Environment
  |            |
  |             ----- global              # Resources created in the us-east-1 region
  |            |
  |             ----- regional            # Resources created in the local region
  |
  docs                                    # Diagrams and documentation
  |
  scripts                                 # Various helper scripts
  |
  templates                               # The Cloud Formation templates
```

## Installation and Setup

This repository uses [Sceptre](https://docs.sceptre-project.org/3.2.0/) to orchestrate the creation of the entire system. See below for notes about Sceptre if this is your first time using this technology.

For instructions on installing and setting up the system, please refer to [our installation wiki](https://github.com/CDLUC3/dmp-hub-cfn/wiki/Installation,-Updating-and-Deleting-AWS-resources)

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
