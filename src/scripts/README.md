# Helper Scripts

The scripts in this directory are meant to help you manage the DMPHub system in the AWS environment. Most require you to have your AWS credentials setup (e.g. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) as environment variable.

## General purpose

### resources-ls.sh

This helper script uses the `aws_tag_query.json` to fetch the list of resources by that include the tags:
`Program = uc3`, `Service = dmp`, `SubService = hub`. The environment is dictated by your credentials.
```
> ./resources-ls.sh
Fetching resources tagged with [uc3 dmp hub dev] in the global region (us-east-1) ...
{
    "ResourceIdentifiers": [
        {
            "ResourceArn": "arn:aws:cloudformation:us-east-1:00000:stack/uc3-dmp-hub-dev-global-cloudfront/12345",
            "ResourceType": "AWS::CloudFormation::Stack"
        }
    ]
}
```

### verify_dmp_ids.rb

This ruby script will take in a CSV file that contains DMP-IDs in column one. It will then query both the DMPHub and EZID APIs to determine if the DMP-ID exists in both systems.

Note this requires a `bundle install` before running the first time.
```
> ruby verify_dmp_ids.rb prd ezid_orphans_2024-02-01.csv
Checking each DMP-ID in the CSV file to determine if it exists in the DMPHub and EZID.
This script will only report when a DMP-ID does not appear in one of those systems
...
DMP-ID: '10.48321/D1001B' -- in DMPHub? false -- in EZID? true
DMP-ID: '10.48321/D1002Q' -- in DMPHub? false -- in EZID? true
DMP-ID: '10.48321/D1101N' -- in DMPHub? false -- in EZID? false
```

## Dynamo management

In the event that you need to manually insert an entry into the DynamoTable, you can use a converter to transform regular JSON (e.g. a DMP-ID) via sites like [Dynobase](https://dynobase.dev/dynamodb-json-converter-tool/)

### seed_dynamo.sh

This script will seed the DynamoTable with the initial Provenance and Augmenter records. It is triggered by the Sceptre dynamo config as a hook. You must include 3 arguments, the environment, the name of your UI system that will be the primary source of your DMP-IDs and that system's URL. For example:
`> ./seed_dynamo.sh dev MySystem my-system.org`

## EZID management

### ezid_download.sh

This script is from the EZID website and can be used to fetch a list of all your EZIDs. You can filter by a number of options. The initial use case was to find any EZID records that still pointed to the old DMPHub system after the migration.

For more info see the [EZID docs](https://ezid.cdlib.org/doc/apidoc.html#batch-download). Here is an example:
```
> ./ezid_download.sh [username] [password] format=csv type=doi datacite=yes column=_target column=datacite.title column=_created convertTimestamps=yes
submitting download request...
waiting........
7iXZ8WDv6BIFFMUt.csv.gz
```

### ezid_sync.sh

This script is used to Trigger the EZIDPublisher Lambda to publish a DMP ID's current metadata from the DynamoTable to EZID. A common use case for this is if the EzidPublisher Lambda encountered an error or if we have paused submissions to EZID and we now want to go through and re-run them when the system is back online.

```
> ./ezid_sync.sh dev doi.org/10.12345/A1B2C3
Verifying existence of {"PK":{"S":"DMP#doi.org/10.12345/A1B2C3"},"SK":{"S":"VERSION#latest"}}
Triggering EZID sync
{ "FailedEntryCount": 0, "Entries": [ { "EventId": "1b2c4597-8eb6-5372-8d5a-9a067431d9ab" } ] }
```

### convert_old_dmphub_to_dynamo.rb

This script was used to migrate DMP-IDs that were in the original DMPHub but not in the DMPTool. During the initial EAGER project we manually added some DMPs that had known outputs in the DataCite ecosystem so that we could do a proof of concept.

It should not need to be used again, but contains some useful code that could be used for future projects
