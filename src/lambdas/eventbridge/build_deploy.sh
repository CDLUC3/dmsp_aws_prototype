#!/bin/bash

if [ $# -ne 2 ]; then
  echo 'Expected the env and function name to be passed as arguments! (e.g. `./build_deploy.sh dev citer`)'
  exit 1
fi

# Structure the LambdaName Tag as `env-name`. This will be used by the LambdaPublisher Lambda Function
# to auto deploy the Function once it is uploaded to S3. The `name` should match the suffix of the Function Name.
#   E.g. if the Function name is `uc3-dmp-hub-dev-lambdas-foo`, then the name should be `foo`
export LAMBDA_NAME="$1-$2"

export S3_BUCKET=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3PrivateBucketId" | jq .Parameter.Value | sed -e "s/\"//g")
if [ -z $S3_BUCKET ]; then echo "No S3 Bucket found!"; exit 1; fi

# Zip up the function code
zip "$LAMBDA_NAME.zip" ./*.rb

# Upload the Zip to S3 and tag it so the LambdaPublisher Lambda Function can deploy it
aws s3api put-object --bucket $S3_BUCKET \
                     --key "lambdas/$LAMBDA_NAME.zip" \
                     --body "$LAMBDA_NAME.zip" \
                     --tagging "Env=$1&NameSuffix=$2"
