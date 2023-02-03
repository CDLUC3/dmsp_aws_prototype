#!/bin/bash

ARN_PREFIX=arn:aws:s3:::

if [ $# -ne 2 ]; then
  echo 'Wrong number of arguments. Expecting 1: The `env` for your samconfig.toml'
  exit 2
fi

echo "Fetching resource ARNs needed for SAM template.yaml"

# aws sam --parameter-overrides ParameterKey=Key1,ParameterValue=value1 ParameterKey=Key2,ParameterValue=value2

if [ -f "$FILE" ]; then
  if [ -f "$HTML" ]; then
    echo "Searching for S3 buckets with name like: *dmp-hub-$1*"
    for bucket in `aws resource-groups search-resources --resource-query file://$FILE | jq .ResourceIdentifiers[].ResourceArn`; do
      if [[ "$bucket" == *"cloudfront"* ]]; then
        name="s3://$(echo $bucket | sed -e "s/\"//g" | sed -e "s/$ARN_PREFIX//")"
        CF_S3_BUCKET=$name
        break
      fi
    done

    echo "No S3 buckets matched the name you provided: $1"
  else
    echo "Expecting to find an index.html in this directory!"
  fi
else
  echo "Expecting to find a JSON query file, $FILE, for AWS CLI command `resource-groups` query~"
fi
