# DMPHub
         _                 _           _
      __| |   _  _   ___  | |__  _   _| |_
     / _` |  / \/ \ |  _ \| `_ \| | | | '_ \
    | (_| | / /\/\ \| | ) | | | | |_| | |_) |
     \__,_|/_/    \_| '__/|_| |_|_____|_'__/
                    |_|

This repository manages both the application logic and the infrastructure for the DMPHub metadata repository.
It works in conjunction with the [dmp-hub-ui repository](https://github.com/CDLUC3/dmp-hub-ui) which contains the source code for the React UI.

<img src="docs/architecture.png?raw=true">

## CloudFormation via Sceptre

This repository uses the [AWS Serverless Application Model (SAM)](https://aws.amazon.com/serverless/sam/) to manage the AWS API Gateway and Lambda resources. It uses [Sceptre](https://github.com/Sceptre/sceptre) to manage the remaining resources via [AWS Cloud Formation](https://aws.amazon.com/cloudformation/).

The entire initial build process however is managed by Sceptre. Sceptre has a hook that will build the SAM application once the resources it depends on (e.g. DynamoDb Table) have been created.

Directory structure:
```
     config
     |  |
     |   ----- [env]          # Sceptre configs by Environment (each config corresponds to a template)
     |
     docs                     # Diagrams and documentation
     |
     src                      # The SAM managed code
     |  |
     |   ----- functions      # The lambda functions
     |  |
     |   ----- layers         # The lambda layers
     |  |
     |   ----- spec           # Tests for the functions and layers
     |  |
     |   ----- template.yaml  # The SAM Cloud Formation template
     |
     templates                # The Cloud Formation templates (each template corresponds to a config)
```

## Installation

You will need to install a few things before you're able to build the application. Please note that this system uses Amazon Web Services (AWS). You will create an account if you do not already have one.

_**Please note that building this application will create resources in your account that will incur charges!**_

### AWS resource prerequisites

You will need to have a VPC and Subnets defined and available to house the resources built by this repository. You will also need to have a Hosted Zone defined so that the SSL Certificate and Route53 resources can be constructed.

We recommend exporting the VPC, Subnet and Hosted Zone IDs as stack outputs if they were constructed via Cloud Formation. If they were not built by Cloud Formation, then you can place them in SSM parameters.

Once you've identified these ids you will need to update the following Sceptre config files: `cert.yaml`, `cognito.yaml`, `config.yaml` and `route53.yaml`

### AWS credentials
You must have your [AWS credentials setup on your system](https://docs.aws.amazon.com/sdk-for-java/v1/developer-guide/setup-credentials.html) in order to build the application and infrastructure.

You will also need to install the [AWS CLI](https://aws.amazon.com/cli/)

### Sceptre installation and setup
Ensure Python is installed: `python --version`

Assuming it is, install pipenv (Python package mamnager) :`pip install --user pipenv`

Then install Sceptre: `pip install sceptre`

Make sure the install was successful: `sceptre --version`

Update Sceptre (at any time): `pip install sceptre -U`

### Install UC3 Sceptre utilities

Clone the [uc3-sceptre-utils repository](https://github.com/CDLUC3/uc3-sceptre-utils)

Build and install the python based resolvers and hooks for Sceptre: `pip install ./`

### Required SSM parameters

The following SSM parameters must be setup manually in your AWS account prior to installation. Note that the instructions below use the AWS CLI but you may set them up through the AWS console as well.

Add your administrator email to the SSM parameter store. This email will receive fatal error messages produced by the Lambdas
- Admin email: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/AdminEmail --value "[email]" --type "String"`

**Note:** After the sqs.yaml stack is created, AWS will send an email to the address you define in the `AdminEmail` parameter. You will need to click the link in that email to confirm the subscription!

The following SSM parameters should be defined for integration with EZID for registering DOIs:
- EZID api url (e.g. `https://ezid-stg.cdlib.org/`): `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidApiUrl --value "[url]" --type "String"`
- EZID base url (the prefix for the DOI - e.g. `https://doi.org/`): `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidBaseUrl --value "[url]" --type "String"`
- EZID debug mode: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidDebugMode --value "true" --type "Boolean"`
- EZID hosting institution: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidHostingInstitution --value "[name]" --type "String"`
- EZID password: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidPassword --value "[password]" --type "SecureString"`
- EZID shoulder: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidShoulder --value "[shoulder]" --type "String"`
- EZID username: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/EzidUsername --value "[username]" --type "SecureString"`

If you have any external systems that will be communicating with the DMPHub API, you will need to add any OAuth client credentials required by that external system. This will be used when attempting to download DMP PDF docuemnts and/or send updated metadata back to the external system. __Note that the `system_key` in the examples below MUST match the PK value for the external system in the Dynamo table. (e.g. the `PROVENANCE#example` Dyanmo item would result in an ssm parameter of `/uc3/dmp/hub/[env]/example/client_id`). See below for an example Provenance item.
- Client id: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/[system_key]/client_id --value "[username]" --type "SecureString"`
- Client secret: `aws ssm put-parameter --name /uc3/dmp/hub/[env]/[system_key]/client_secret --value "[username]" --type "SecureString"`

You can use `aws ssm get-parameters-by-path --path '/uc3/dmp/hub/[env]/'` to see what parameters have already been set.

Any new parameters should maintain the `/uc3/dmp/hub/[env]/` prefix!

## DynamoDB Table Items

### Sample Provenance item:
The following JSON object represents a provenance system record. All provenance system records have a Partition Key (PK) that begins with the `PROVENANCE#` prefix and a Sort Key (SK) that is equal to `PROFILE`.

```
{
  "PK": "PROVENANCE#example",
  "SK": "PROFILE",
  "contact": {
    "email": "admin@example.com",
    "name": "Example system administrator"
  },
  "description": "An external system",
  "downloadUri": "https://example.com/api/dmps/",
  "homepage": "https://example.com",
  "name": "Example System",
  "redirectUri": "https://example.com/callback",
  "seedingWithLiveDmpIds": true,
  "tokenUri": "https://example.com/oauth/token"
}
```
Explanation of Provenance item attributes:
- **PK** - **required** A unique partition key for the external system. Note that it must start with `PROVENANCE#`
- **SK** - **required** The sort key (do not change this)
- **contact** - **required** The primary technical contact for the external system (displayed in the UI)
- **description** - A description of the external system (displayed in the UI)
- **downloadUri** - The endpoint that the DMPHub can use to download the DMP as a PDF (if applicable). The specific location of the PDF is embedded in the DMP's JSON as a `dmproadmap_related_identifier` with the `"descriptor": "is_metadata_for"` and `"work_type": "output_management_plan"`. Note that the system will first check that the target of that related identifier matches the downloadUri defined here (e.g. https://example.org/dmps/download/). If it does not match, an error is raised. This prevents downloads from unknown/unverified locations
- **homepage** - **required** The landing page for the external system (displayed in the UI)
- **name** - **required** The name of the external system (displayed in the UI)
- **redirectUri** - The URI that the DMPHub can use to send updates about the DMP. For example if the DMPHub learns of a grant ID that was associated with the DMP, it will send that information back to external system via this URI.
- **seedingWithLiveDmpIds** - Flag that can be used when seeding DMPs from an external system to the DMPHub this flag will use the provided DMP ID instead of minting a new one with EZID. __Note that the DMP ID targets would need to be updated with the minting authority
so that they point to the new DMPHub landing page.__ (default is false)
- **tokenUri** - The endpoint the DMPHub should use to obtain an access token that can be used when calling the downloadUri and redirectUri (if applicable). Note that the tokenUri works in conjunction with 2 SSM parameters (note that the 'example' must match the PK value for the item!): `/uc3/dmp/hub/dev/example/client_id`, `/uc3/dmp/hub/dev/example/client_secret`

### Sample DMP item (complete metadata):
The following JSON object represents a DMP item in the Dynamo table.
```
{
  "PK": "DMP#doi.org/10.12345/A1.1A2B3C4D6",
  "SK": "latest",
  "contact": {
    "contact_id": {
      "identifier": "https://orcid.org/0000-0000-0000-0000",
      "type": "orcid"
    },
    "mbox": "jane.doe@example.com",
    "name": "Doe, Jane"
  },
  "contributor": [
    {
      "affiliation": {
        "affiliation_id": {
          "identifier": "https://ror.org/12344556",
          "type": "ror"
        },
        "name": "Example University"
      },
      "contributor_id": {
        "identifier": "https://orcid.org/0000-0000-0000-0000",
        "type": "orcid"
      },
      "mbox": "Jane.Doe@example.com",
      "name": "Doe, Jane",
      "role": [
        "http://credit.niso.org/contributor-roles/data-curation",
        "http://credit.niso.org/contributor-roles/investigation"
      ]
    },
    {
      "affiliation": {
        "affiliation_id": {
          "identifier": "https://ror.org/23864587935",
          "type": "ror"
        },
        "name": "Another University"
      },
      "mbox": "someone.else@example.org",
      "name": "Else, Someone",
      "role": [
        "http://credit.niso.org/contributor-roles/project-administration"
      ]
    },
    {
      "name": "So PhD., So N.",
      "role": [
        "http://credit.niso.org/contributor-roles/investigation"
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
  "created": "2021-11-08T19:06:04Z",
  "dataset": [
    {
      "dataset_id": {
        "identifier": "1550",
        "type": "other"
      },
      "data_quality_assurance": [
        "We will verify the quality of all data collected during this project through a third party."
      ],
      "description": "<p>A collection of radiographic images of coral.</p>",
      "distribution": [
        {
          "data_access": "open",
          "host": {
            "description": "The test data repository for oceanographic information.",
            "dmproadmap_host_id": {
              "identifier": "https://www.re3data.org/api/v1/repository/r3d0000000000000",
              "type": "url"
            },
            "title": "Generic Ocean Information Data Repository",
            "url": "http://example.org/repo"
          },
          "license": [
            {
              "license_ref": "https://spdx.org/licenses/CC-BY-4.0.json",
              "start_date": "2021-05-18T00:00:00Z"
            }
          ],
          "title": "Anticipated distribution of coral images"
        }
      ],
      "issued": "2026-05-18T00:00:00Z",
      "keyword": [
        "Earth and related environmental sciences",
        "Coral"
      ],
      "metadata": [
        {
          "description": "Example Core - a tests metadata standard",
          "metadata_standard_id": {
            "identifier": "https://rdamsc.bath.ac.uk/api2/2485ty247y7t9y429t4295t",
            "type": "url"
          }
        }
      ],
      "personal_data": "unknown",
      "preservation_statement": "The images will be depositied in a repository and made available until 2050",
      "security_and_privacy": [
        {
          "title": "Data security",
          "description": "We're going to encrypt this one."
        }
      ],
      "sensitive_data": "unknown",
      "technical_resource": [
        {
          "name": "Example University's thermal imaging camera 1234",
          "description": "A super powerful thermal imaging camera"
        }
      ],
      "title": "Images of brain coral time series",
      "type": "dataset"
    }
  ],
  "description": "<p>The example data management plan for the DMPHub.</p>",
  "dmphub_created_at": "2022-11-29T19:49:08+00:00",
  "dmphub_modification_day": "2022-11-29",
  "dmphub_provenance_id": "PROVENANCE#example",
  "dmphub_provenance_identifier": "https://example.com/dmps/989898",
  "dmphub_updated_at": "2022-11-29T19:49:08+00:00",
  "dmproadmap_external_system_identifier": "989898",
  "dmproadmap_privacy": "public",
  "dmproadmap_related_identifiers": [
    {
      "descriptor": "describes",
      "identifier": "https://doi.org/10.21966/1.566666",
      "type": "doi",
      "work_type": "dataset"
    },
    {
      "descriptor": "references",
      "identifier": "https://doi.org/10.5281/zenodo.5719523",
      "type": "doi",
      "work_type": "article"
    },
    {
      "descriptor": "is_metadata_for",
      "identifier": "https://example.com/api/v2/dmps/989898.pdf",
      "type": "url",
      "work_type": "output_management_plan"
    },
    {
      "descriptor": "is_new_version_of",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-10-03T08:41:32+00:00",
      "type": "url",
      "work_type": "output_management_plan"
    }
  ],
  "dmp_id": {
    "identifier": "https://doi.org/10.12345/A1.1A2B3C4D6",
    "type": "doi"
  },
  "ethical_issues_description": "We will need to ensure that we anonymie our data",
  "ethical_issues_exist": "yes",
  "ethical_issues_report": "https://example.edu/privacy_policy",
  "language": "eng",
  "modified": "2022-11-14T22:18:18Z",
  "project": [
    {
      "description": "Our sample project for the DMPHub.",
      "end": "2024-11-29T19:48:57Z",
      "funding": [
        {
          "funder_id": {
            "identifier": "https://ror.org/0000000000",
            "type": "ror"
          },
          "funding_status": "granted",
          "name": "National Funding Institute",
          "grant_id": {
            "type": "other",
            "identifier": "34562356
        }
      ],
      "start": "2015-05-12T00:00:00Z",
      "title": "DMPHub example DMP project."
    }
  ],
  "title": "Example DMP record for the DMPHub."
}
```
Explanation of DMP item attributes that are used internally by the DMPHub and are relevant internally and NOT distributed in API callers. For a full explanation of the other DMP attributes, please see the API documentation in the wiki:
- **PK** - **required** A unique partition key for the DMP which equates to it's DMP ID (DOI). Note that it must start with `DMP#`
- **SK** - **required** The sort key which represents the DMP version. The most current version is always `VERSION#latest` and prior versions use a date time stamp in UTC (e.g. `VERSION#2022-10-03T09:15:32+00:00`)
- **"dmphub_created_at** - The date time stamp (UTC) of when the original version of the DMP was added to the DMPHub. This value remains the same regardless of the version (e.g. `2022-10-03T09:15:32+00:00`).
- **dmphub_modification_day** - The date of the version (UTC) (e.g. `2022-11-29`) which is used to facilitate querying and sorting.
- **dmphub_provenance_id** - The `PK` of the Provenance system that created the DMP (e.g. `PROVENANCE#example`)
- **dmphub_provenance_identifier** - The Provenance system's internal identifier for the DMP. This is used in conjunction with the Provenance system's `redirectUri` to send updates to the Provenance system (e.g. `https://example.com/dmps/989898` or `989898`)
- **dmphub_updated_at** - The date time stamp (UTC) that this version of the DMP was added to the DMPHub. This value is used to create the official version `SK` the next time an update is made to the DMP.

## DMP versioning strategy
As noted above, the latest version of the DMP always has the Sort Key (SK) or `VERSION#latest`. Prior versions use the `modified` value of the DMP at the time of the update `VERSION#2022-12-15T11:42:15+00:00`.

The system also generates `dmproadmap_related_identifiers` that can be used to traverse between DMP versions. Each DMP is only aware of it's immediate ancestor and which version followed it.

To illustrate this, consider a DMP that has 4 versions. When viewing the `VERSION#latest` of a DMP we will see a link to the prior version in the array:
```
{
  "SK": "VERSION#latest",
  "dmproadmap_related_identifiers": [
    {
      "descriptor": "is_new_version_of",
      "work_type": "output_management_plan",
      "type": "url",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-10-09T08:07:06+00:00"
    }
  ]
}
```
When viewing that '2022-10-09' prior version, we will see a link to the latest version as well as a link to the version of the DMP that it replaced.
```
{
  "SK": "VERSION#2022-10-09T08:07:06+00:00",
  "dmproadmap_related_identifiers": [
    {
      "descriptor": "is_previous_version_of",
      "work_type": "output_management_plan",
      "type": "doi",
      "identifier": "https://doi.org/10.12345/ABC123"
    },
    {
      "descriptor": "is_new_version_of",
      "work_type": "output_management_plan",
      "type": "url",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-05-04T03:02:01+00:00"
    }
  ]
}
```
When we follow that link to the prior '2022-05-04' version we will see a link to the '2022-10-09' version we were just looking at as well as a link to the original '2022-01-01' version:
```
{
  "SK": "VERSION#2022-05-04T03:02:01+00:00",
  "dmproadmap_related_identifiers": [
    {
      "descriptor": "is_previous_version_of",
      "work_type": "output_management_plan",
      "type": "url",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-10-09T08:07:06+00:00"
    },
    {
      "descriptor": "is_new_version_of",
      "work_type": "output_management_plan",
      "type": "url",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-01-01T01:01:01+00:00"
    }
  ]
}
```
When we finally drill through to the original '2022-01-01' version we will only find a link back to the '2022-05-04' version:
```
{
  "SK": "VERSION#2022-01-01T01:01:01+00:00",
  "dmproadmap_related_identifiers": [
    {
      "descriptor": "is_previous_version_of",
      "work_type": "output_management_plan",
      "type": "url",
      "identifier": "https://example.com/api/v0/10.12345/A1.1A2B3C4D6?version=2022-05-04T03:02:01+00:00"
    }
  ]
}
```

### Sample DMP metadata amendments from another system

When DMPs are created, a `dmphub_provenance_id` is recorded in the the DMP JSON. This is used to define the system of provenance. When another system apends metadata to the DMP, it's provenance is recorded. These provenance markers help prevent systems from overwriting one another's changes and also help determine when a new version should be created.

```
{
  "dmp": {
    "PK": "DMP#doi.org/10.12345/A1.1A2B3C4D6",
    "SK": "latest",
    "dmphub_provenance_id": "PROVENANCE#example",
    "title": "Example complete DMP",
    "dmp_id": {
      "type": "doi",
      "identifier": "https://doi.org/10.12345/A1.1A2B3C4D5"
    },
    "project": [
      {
        "title": "Example research project",
        "funding": [
          {
            "name": "National Funding Organization",
            "funder_id": {
              "type": "fundref",
              "identifier": "http://dx.doi.org/10.13039/100005595"
            }
            "funding_status": "granted",
            "grant_id": {
              "type": "url",
              "identifier": "https://awards.example.fund/1213424"
            },
            "dmphub_provenance_id": "PROVENANCE#funder123"
          }
        ]
      }
    ]
  }
}
```

## Notes about Sceptre

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

Sceptre will place a copy of the compiled/aggregated CF template into the S3 bucket defined in the stack's root config.yaml. You can also inspect the stack in the AWs console to see the resources created, outputs defined, along with the logs.

### Creating new stacks

Create an env specific config directory: `mkdir config/dev && touch config/dev/config.yaml`

Create a new Cloud Formation (CF) template: `touch templates/resource.yaml config/dev/resource.yaml`

Create/build a stack (will fail if you've already created the stack): `sceptre create dev/reesource.yaml`

Update a stack after changing a config or template: `sceptre update dev/resource.yaml`

Delete a stack (will delete the actual resource!): `sceptre delete dev/resource.yaml`

## Testing API access for system-to-system integrations

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
