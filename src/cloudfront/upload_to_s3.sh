#!/bin/bash

TAG_QUERY=aws_tag_query.json
HTML=src/cloudfront/index.html

ARN_PREFIX=arn:aws:s3:::

if [ $# -ne 1 ]; then
  echo 'Wrong number of arguments. Expecting 1: S3 Bucket name. Note the bucket name can be a partial name.'
  exit 2
fi

if [ -f "$TAG_QUERY" ]; then
  if [ -f "$HTML" ]; then
    echo "Searching for S3 buckets with name like: *$1*"

    for bucket in `aws resource-groups search-resources --resource-query file://$TAG_QUERY | jq .ResourceIdentifiers[].ResourceArn`; do
      # echo $bucket

      if [[ "$bucket" == *"$1"* ]]; then
        name="s3://$(echo $bucket | sed -e "s/\"//g" | sed -e "s/$ARN_PREFIX//")"
        echo "Detected S3 Bucket: $name"

        aws s3 cp $HTML $name
        exit 0
      fi
    done

    echo "No S3 buckets matched the name you provided: $1"
  else
    echo "Expecting to find an index.html in this directory!"
  fi
else
  echo "Expecting to find a JSON query file, $FILE, for AWS CLI command `resource-groups` query~"
fi
