         _                 _           _          _   _
      __| |   _  _   ___  | |__  _   _| |_       | | | |
     / _` |  / \/ \ |  _ \| `_ \| | | | '_ \     | | | |
    | (_| | / /\/\ \| | ) | | | | |_| | |_) |    | | | |
     \__,_|/_/    \_| '__/|_| |_|_____|_'__/     |_| |_|
 -------------------|-|-------------------------------------

This repository manages the infrastructure of the DMPHub 2.0 in the AWS environment

<img src="architecture-v4.png?raw=true">

## CloudFormation via Sceptre

This directory uses [Sceptre](https://github.com/Sceptre/sceptre) to manage AWS CloudFormation templates and stacks.

Directory structure:
```
     config
     |
      ----- [env]   # Sceptre stack config by Environment
              |
               ---- application    # The Application logic (Lambdas)
              |
               ---- data    # The resources that should be persistent (e.g. Dynamo, S3)
              |
               ---- frontend    # The resources that interact with http requests (e.g. WAF, Cognito)
              |
               ---- management    # The general system management components (e.g. CloudWatch, SSM vars)
              |
               ---- pipeline    # The CodeBuild and CodePipeline for the Lambda code
     |
     |
      ----- templates   # the CF templates
```

### Notes about Sceptre
AWS Resource names are auto-constructed by Sceptre using the "${project_name}-${stack-name}-${yaml-name}-${resource-id}" format.
For example a sceptre project directory like this:
```
my-project (defined in the root `config/config.yaml` file)
    |
     ---- config
    |      |
    |       ------ dev
    |               |
    |                ----- application.yaml
    |
     ---- templates
             |
              ----- application.yaml (containing a resource called ExampleBucket)
```
With the s3-bucket.yaml template containing:
```
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  ExampleBucket:
    Type: AWS::S3::Bucket
```
Would result in a BucketName of "my-project-dev-application-ExampleBucket-[unique-id]"

Sceptre will place a copy of the compiled/aggregated CF template into the S3 bucket defined in the stack's root config.yaml

### Sceptre installation and setup
Ensure Python is installed: `python --version`

Assuming it is, install pipenv (Python package mamnager) :`pip install --user pipenv`

Then install Sceptre: `pip install sceptre`

Make sure the install was successful: `sceptre --version`

Update Sceptre (at any time): `pip install sceptre -U`

Install the Sceptre SSM resolver: `pip install sceptre-ssm-resolver`

Build the project directory: `sceptre new project uc3-dmp-hub`

### SSM parameter setup

The following SSM parameters should be defined:
- EZID username: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidUsername --value "[username]" --type "SecureString"`
- EZID password: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidPassword --value "[password]" --type "SecureString"`
- EZID hosting institution: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidHostingInstitution --value "[name]" --type "String"`
- EZID shoulder: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidShoulder --value "[shoulder]" --type "String"`
- EZID debug mode: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidDebugMode --value "true" --type "Boolean"`

You can use `aws ssm get-parameters-by-path --path '/uc3/dmp/hub/[env]/'` to see what parameters have already been set.

Any new parameters should maintain the `/uc3/dmp/hub/[env]/` prefix!

### Creating new stacks

Create an env specific config directory: `mkdir config/dev && touch config/dev/config.yaml`

Create a new Cloud Formation (CF) template: `touch templates/resource.yaml config/dev/resource.yaml`

Create/build a stack (will fail if you've already created the stack): `sceptre create dev/reesource.yaml`

Update a stack after changing a config or template: `sceptre update dev/resource.yaml`

Delete a stack (will delete the actual resource!): `sceptre delete dev/resource.yaml`


## Verifying the stack

### Testing API access for system-to-system integrations

Ensure that you can authenticate and receive back avalid JWT (the credentials can be found in the AWS console under the Cognito user pool's app integration section)
```
curl -vL -X POST \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=client_credentials&client_id=[client_id]&client_secret=[client_secret]&scope=https://dmphub2-dev.cdlib.org/api.read' \
  https://uc3-dmp-hub-systems-user-pool.auth.us-west-2.amazoncognito.com/token
```

Then verify that you can access the API endpoints (not the :domain can be found in the AWS console under the Api Gatway's stack)
```
curl -v -H 'Accept: application/json' \
        -H 'Authorization: [token]'
        https://[domain]/v0/dmps
```
