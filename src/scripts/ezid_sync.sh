#!/bin/bash

if [ $# -ne 2 ]; then
  echo 'Expected the env and DMP ID to be passed as arguments! (e.g. `./ezid_sync.sh dev doi.org/10.12345/A1B2C3`)'
  exit 1
fi

ENV="$1"
if [ -z "$3" ]; then
  AWS_REGION='us-west-2'
else
  AWS_REGION=$3
fi

QUERY="Stacks[0].Outputs[?OutputKey==\`DomainName\`].OutputValue"
DOMAIN=$(aws cloudformation describe-stacks --stack-name "uc3-dmp-hub-$ENV-global-route53" --query $QUERY --output text --region 'us-east-1')

QUERY="Stacks[0].Outputs[?OutputKey==\`DynamoTableName\`].OutputValue"
TABLE=$(aws cloudformation describe-stacks --stack-name "uc3-dmp-hub-$ENV-regional-dynamo" --query $QUERY --output text --region $AWS_REGION)

QUERY="Stacks[0].Outputs[?OutputKey==\`EventBusName\`].OutputValue"
BUS=$(aws cloudformation describe-stacks --stack-name "uc3-dmp-hub-$ENV-regional-eventbridge" --query $QUERY --output text --region $AWS_REGION)

QUERY="Stacks[0].Outputs[?OutputKey==\`Uc3PrdOpsCfnServiceRoleArn\`].OutputValue"
ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "uc3-ops-aws-$ENV-iam" --query $QUERY --output text --region $AWS_REGION)

FAIL=0
if [ -z $DOMAIN ]; then echo "No DomainName found!"; FAIL=1; fi
if [ -z $TABLE ]; then echo "No DynamoTableName found!"; FAIL=1; fi
if [ -z $BUS ]; then echo "No EventBusName found!"; FAIL=1; fi
if [ -z $ROLE_ARN ]; then echo "No RoleArn found!"; FAIL=1; fi
if [ $FAIL == 1 ]; then exit 2; fi

KEY="{\"PK\":{\"S\":\"DMP#$2\"},\"SK\":{\"S\":\"VERSION#latest\"}}"

echo "Verifying existence of $KEY"
DMP=$(aws dynamodb get-item --table-name $TABLE --key $KEY --projection-expression 'PK' --region $AWS_REGION)
if [[ $DMP != *"Item"* ]]; then echo "Item does not exist in the Dynamo Table!"; exit 3; fi

echo "Triggering EZID sync"
SOURCE="$DOMAIN:lambda:event_publisher"
DETAIL_TYPE="EZID%20update"
DETAIL="{\\\"PK\\\":\\\"DMP#$2\\\",\\\"SK\\\":\\\"VERSION#latest\\\",\\\"dmphub_provenance_id\\\":\\\"dmptool\\\"}"
ENTRY="[{\"Source\":\"$SOURCE\",\"DetailType\":\"$DETAIL_TYPE\",\"Detail\":\"$DETAIL\",\"EventBusName\":\"$BUS\"}]"
EVENT=$(aws events put-events --entries $ENTRY --region $AWS_REGION)
echo $EVENT
