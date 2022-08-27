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

## Sample DynamoDB Table Items

Sample Provenance item:
```
{
 "PK": "PROVENANCE#example",
 "SK": "PROFILE",
 # Only used when transferring DMPs from another system and we do not want to register our own
 # DMP IDs for those records
 "can_predefine_dmp_ids": true,
 "contact": {
  "email": "jane.doe@example.com",
  "name": "Jane Doe"
 },
 "description": "An example system",
 "homepage": "https://example.com",
 "name": "Example DMP authoring system",
 # The API endpoint that we can call to send updated information about the DMP (if applicable)
 "redirectUri": "https://example.com/api/dmps/callback"
}
```

Sample DMP item (minimal metadata):
```
{
 "PK": "DMP#doi.org/10.12345/A1.1A2B3C4D5",
 "SK": "VERSION#latest",
 "contact": {
  "contact_id": {
   "identifier": "https://orcid.org/0000-0000-0000-000X",
   "type": "orcid"
  },
  "mbox": "jane@example.edu",
  "name": "jane doe"
 },
 "created": "2022-05-24T12:33:44Z",
 "dataset": [],
 "dmphub_created_at": "2022-08-25T16:24:56+00:00",
 "dmphub_modification_day": "2022-08-25",
 "dmphub_provenance_id": "PROVENANCE#example",
 "dmphub_provenance_identifier": "https://example.com/api/dmps/callback/45645",
 "dmphub_updated_at": "2022-08-25T16:24:56+00:00",
 "dmp_id": {
  "identifier": "https://doi.org/10.12345/A1.1A2B3C4D5",
  "type": "doi"
 },
 "modified": "2022-05-24T12:33:44Z",
 "project": [],
 "title": "Example minimal DMP"
}
```

Sample DMP item (complete metadata):
```
{
  "dmp": {
    "PK": "DMP#doi.org/10.12345/A1.1A2B3C4D6",
    "dmphub_provenance_id": "PROVENANCE#example",
    "title": "Example complete DMP",
    "description": "An exceptional example of complete DMP metadata",
    "language": "eng",
    "created": "2021-11-08T19:06:04Z",
    "modified": "2022-01-28T17:52:14Z",
    "ethical_issues_description": "We may need to anonymize user data",
    "ethical_issues_exist": "yes",
    "ethical_issues_report": "https://example.edu/privacy_policy",
    "dmp_id": {
      "type": "doi",
      "identifier": "https://doi.org/10.12345/A1.1A2B3C4D5"
    },
    "contact": {
      "name": "Jane Doe",
      "mbox": "jane.doe@example.com",
      "dmproadmap_affiliation": {
        "name": "Example University (example.com)",
        "affiliation_id": {
          "type": "ror",
          "identifier": "https://ror.org/1234567890"
        }
      },
      "contact_id": {
        "type": "orcid",
        "identifier": "https://orcid.org/0000-0000-0000-000X"
      }
    },
    "contributor": [
      {
        "name": "Jane Doe",
        "mbox": "jane.doe@example.com",
        "role": [
          "http://credit.niso.org/contributor-roles/data-curation",
          "http://credit.niso.org/contributor-roles/investigation"
        ],
        "dmproadmap_affiliation": {
          "name": "Example University (example.com)",
          "affiliation_id": {
            "type": "ror",
            "identifier": "https://ror.org/1234567890"
          }
        },
        "contributor_id": {
          "type": "orcid",
          "identifier": "https://orcid.org/0000-0000-0000-000X"
        }
      }, {
        "name":"Jennifer Smith",
        "role": [
          "http://credit.niso.org/contributor-roles/investigation"
        ],
        "dmproadmap_affiliation": {
          "name": "University of Somewhere (somwhere.edu)",
          "affiliation_id": {
            "type": "ror",
            "identifier": "https://ror.org/0987654321"
          }
        }
      }, {
        "name": "Sarah James",
        "role": [
          "http://credit.niso.org/contributor-roles/project_administration"
        ]
      }
    ],
    "cost": [
      {
        "currency_code": "USD",
        "title": "Preservation costs",
        "description": "The estimated costs for preserving our data for 20 years",
        "value": 10000
      }
    ],
    "dataset": [
      {
        "type": "dataset",
        "title": "Odds and ends",
        "description": "Collection of odds and ends",
        "issued": "2022-03-15",
        "keyword": [
          "foo"
        ],
        "dataset_id": {
          "type": "doi",
          "identifier": "http://doi.org/10.99999/8888.7777"
        },
        "language": "eng",
        "metadata": [
          {
            "description": "The industry standard!",
            "language": "eng",
            "metadata_standard_id": {
              "type": "url",
              "identifier": "https://example.com/metadata_standards/123"
            }
          }
        ],
        "personal_data": "no",
        "data_quality_assurance": [
          "We will ensure that the preserved copies are of high quality"
        ],
        "preservation_statement": "We are going to preserve this data for 20 years",
        "security_and_privacy": [
          {
            "title": "Data security",
            "description": "We're going to encrypt this one."
          }
        ],
        "sensitive_data": "yes",
        "technical_resource": [
          {
            "name": "Elctron microscope 1234",
            "description": "A super electron microscope"
          }
        ],
        "distribution": [
          {
            "title": "Distribution of 'Odds and Ends' to 'Random repo'",
            "access_url": "https://example.edu/datasets/00000",
            "download_url": "https://example.edu/datasets/00000.pdf",
            "available_until": "2052-03-15",
            "byte_size": 1234567890,
            "data_access": "shared",
            "format": [
              "application/vnd.ms-excel"
            ],
            "host": {
              "title": "Random repo",
              "url": "A generic data repository",
              "dmproadmap_host_id": {
                "type": "url",
                "identifier": "https://hosts.example.org/765675"
              }
            },
            "license": [
              {
                "license_ref": "https://licenses.example.org/zyxw",
                "start_date": "2022-03-15"
              }
            ]
          }
        ]
      }
    ],
    "language": "eng",
    "project": [
      {
        "title": "Example research project",
        "description": "Abstract of what we're going to do.",
        "start": "2015-05-12T00:00:00Z",
        "end": "2024-05-24T11:32:21-07:00",
        "funding": [
          {
            "name": "National Funding Organization",
            "funder_id": {
              "type": "fundref",
              "identifier": "http://dx.doi.org/10.13039/100005595"
            },
            "funding_status": "granted",
            "grant_id": {
              "type": "url",
              "identifier": "https://nfo.example.org/awards/098765"
            },
            "dmproadmap_funded_affiliations": [
              {
                "name": "Example University (example.edu)",
                "affiliation_id": {
                  "type": "ror",
                  "identifier": "https://ror.org/1234567890"
                }
              }
            ]
          }
        ]
      }
    ],
    "dmproadmap_related_identifiers": [
      {
        "descriptor": "cites",
        "type": "doi",
        "identifier": "https://doi.org/10.21966/1.566666",
        "work_type": "dataset"
      },{
        "descriptor": "is_referenced_by",
        "type": "doi",
        "identifier": "10.1111/fog.12471",
        "work_type": "article"
      }
    ]
  }
}
```