#!/bin/bash

if [ $# -ne 2 ]; then
  echo 'Expected the env and layer name to be passed as arguments! (e.g. `./purge_s3.sh dev eventbridge`)'
  exit 1
fi

export S3_BUCKET=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3PrivateBucketId" | jq .Parameter.Value | sed -e "s/\"//g")
if [ -z $S3_BUCKET ]; then echo "No S3 Bucket found!"; exit 1; fi

aws s3 rm "s3://$S3_BUCKET/lambdas/layers/$1-$2.zip"
