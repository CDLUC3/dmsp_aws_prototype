# DMPHub
         _                 _           _
      __| |   _  _   ___  | |__  _   _| |_
     / _` |  / \/ \ |  _ \| `_ \| | | | '_ \
    | (_| | / /\/\ \| | ) | | | | |_| | |_) |
     \__,_|/_/    \_| '__/|_| |_|_____|_'__/
                    |_|

This repository manages both the application logic and the infrastructure for the DMPHub metadata repository.

It is designed specifically for the Amazon Web Services (AWS) ecosystem. Please note that you must have an AWS account and that building the system will create resources in your account that may incur charges!

<img src="docs/architecture.png?raw=true">

Once all of your AWS resources have been built, you can run `./resources-ls.sh` to see what AWS resources have been created by these CloudFormation templates.

## Directory layout

This repository uses the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) to manage the AWS API Gateway, Lambda functions and other related resources (e.g. IAM policies). It uses [Sceptre](https://github.com/Sceptre/sceptre) to manage the remaining resources (e.g. CloudFront, DynamoDB, etc.) via [AWS CloudFormation](https://aws.amazon.com/cloudformation/).


The Sceptre template for the Dynamo resources contains hooks to: seed the database, run SAM build+deploy, build the React JS landing page (for the DMP ID landing pages) and also build the Swagger API documentation and deploy it to the CloudFront S3 bucket (Note that the Swagger UI is not deployed in the production environment).

Directory structure:
```
     resources-ls.sh                         # A shell script that will show all existing AWS resources for this project
     |
     seed_dynamo.sh                          # A shell script that will seed provenance records in the DynamoDB Table (auto-run by dynamo.yaml config)
     |
     templates                               # The Cloud Formation templates (each template corresponds to a config)
     |
     config
     |  |
     |   ----- [env]                         # Sceptre configs by Environment (each config corresponds to a template)
     |            |
     |             ----- global              # Resources that will be created in the us-east-1 region
     |            |
     |             ----- regional            # Resources that will be created in the local region
     |
     docs                                    # Diagrams and documentation
     |
     src
     |  |
     |   ----- landing_page
     |  |        |
     |  |         ----- public               # Static assets used by the landing page
     |  |        |
     |  |         ----- src                  # The React JS code
     |  |        |
     |  |         ----- build_deploy.rb      # A Ruby script that will perfomr the Node build and deploy to S3
     |  |        |
     |  |         ----- Gemfile              # The dependencies required to run the Ruby script
     |  |        |
     |  |         ----- package.json         # The dependencies for the React JS page
     |  |
     |   ----- swagger
     |  |        |
     |  |         ----- assets               # The Swagger UI CSS and Images
     |  |        |
     |  |         ----- build_openapi_spec.rb # Ruby script that pulls in the latest version of the DMP metadata schema and then deploys the Swagger bundle to the CloudFront S3 bucket which can be accessed via https://dmphub-[env].cdlib.org/api-docs
     |  |        |
     |  |         ----- default_index.html   # The Swagger UI homepage
     |  |        |
     |  |         ----- Gemfile              # The dependencies required to run the Ruby script
     |  |        |
     |  |         ----- package.json         # The dependencies to run the JSON schema to OpenApi converter
     |  |        |
     |  |         ----- v0-api-docs.json     # The Swagger entrypoint
     |  |        |
     |  |         ----- v0-openapi-template.json     # The open API doc (the DMP JSON schema is spliced into this document)
     |  |
     |   ----- sam                           # The SAM managed code
     |           |
     |            ----- functions            # The lambda functions
     |           |
     |            ----- gems                 # The ruby gems that support the functions (they are loaded into the layers)
     |           |
     |            ----- layers               # The lambda layers
     |           |
     |            ----- spec                 # Tests for the functions and layers
     |           |
     |            ----- samconfig.toml       # The SAM configuration file
     |           |
     |            ----- template.yaml        # The SAM Cloud Formation template
     |           |
     |            ----- Gemfile              # The dependencies for the Ruby script that runs SAM build and deploy
     |           |
     |            ----- sam_build_deploy.rb  # A Ruby script that can be used to build and deploy your SAM resources (auto-run by Sceptre's dynamo.yaml config)
```

## Installation and Setup

This repository uses [Sceptre](https://docs.sceptre-project.org/3.2.0/) to orchestrate the creation of the entire system. See below for notes about Sceptre if this is your first time using this technology.

For instructions on installing and setting up the system, please refer to [our installation wiki](https://github.com/CDLUC3/dmp-hub-cfn/wiki/Installation,-Updating-and-Deleting-AWS-resources)

## SAM

AWS SAM is used to manage the API Gateway and all of the Lambda resources. It also contains various Ruby gems used by the Lambda code.

The Sceptre template for Dynamo has a hook that will perform the initial creation of all the SAM managed resources. If you want to make updates or delete these resources you will need to manually run the `cd src/sam && ruby sam_build_deploy.rb dev true true` script. The first arg is the environment, the second boolean arg indicates whether or not to run SAM build and the third boolean arg is whether or not to run SAM deploy.

If you need to update one of the Ruby gems located in `src/samgems` then you will need to:
1. Update the `[gem_dir]/lib/uc3-dmp-[gem_name]/version.rb` file to increment the gem version
2. Run the following from that gem's directory (note you will need to be logged into RubyGems): `rm *.gem && gem build uc3-dmp-[gem_name].gemspec && gem push uc3-dmp-[gem_name]-[version].gem`
3. Once the gem has been uploaded to RubyGems, you can then run cd `src/sam/layers && bundle update uc3-dmp-[gem_name]` to update the LambdaLayer.
4. Then run `cd src/sam && ruby sam_build_deploy.rb [env] true true` to rebuild the LambdaLayer and Functions and deploy them

## Landing Page

The DMP ID landing page is a static React JS webspage that makes an API call to the API Gateway to fetch the JSON for the DMP ID. The JSON is then used to render the page.

For development, you can run `npm start` to compile (and watch) the JS and SCSS files and view the site in your local browser. You will need to know the DMP ID of a valid DMP that currently exists in your development environment.
For example, `http://loclhost:3000/dmps/10.12345/ABCD1234` will fetch the JSON metadata for the latest version of the `10.12345/ABCD1234` DMP ID and render the landing page. If the DMP ID could not be found then React will render a 'Not Found' page.

To build and deploy the ladning page run `ruby build_deploy.rb [env]`

## Swagger

Your CloudFront distribution will contain Swagger API documentation for your API at `https://your.domain.edu/api-docs`. If you modify and redeploy your API Lambdas, you should also update your documentation. to do that:
- Update the `src/swagger/v0-openapi-template.json`
- run: `cd src/swagger && ruby build_openapi_spec.rb dev 4.18.1` (where 4.18.1 is the version of Swagger UI you want to use)

The `"dmp": {}` portion of the `src/swagger/v0-openapi-template.json` file is auto-populated from the latest JSON schema document located in `src/sam/layers/ruby/config/author.json`

Note that the above command is also how you would upgrade Swagger itself. The version number should match one of the [swagger-ui release](https://github.com/swagger-api/swagger-ui/releases) tags

If CloudFront is not displaying the updated Swagger docs, you may need to forcibly clear it's cache. To do that run: `aws cloudfront create-invalidation --distribution-id $DISTO_ID --paths "/api-docs/*" --region $AWS_REGION`

## Testing

Sceptre allows you to test your templates and config prior to building the CloudFormation stacks. You can do this by running `sceptre validate config/[env]/[dir]/[config_file].yaml`.

Note that Sceptre always shows you the change set and asks you to confirm before it will make any changes to your AWS environment.

Tests for the Lambda code and the API Gateway are coming soon ...

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
