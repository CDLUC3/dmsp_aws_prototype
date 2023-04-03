#!/bin/bash

echo ''
echo '===================='
echo 'SAM BUILD AND DEPLOY'
echo '===================='
echo ''

TAG_QUERY=aws_tag_query.json
ARN_PREFIX=arn:aws:s3:::
KEY=ParameterKey
VAL=ParameterValue

if [ $# -ne 3 ]; then
  echo 'Wrong number of arguments. Expecting 3:'
  echo 'The `env` for your samconfig.toml, the Domain name and whether or not to do the LambdaLayer build.'
  echo '  For example: `./src/sam/sam_build_deploy.sh dev example.com true)`'
  exit 1
fi

echo "Fetching resource ARNs from SSM ..."
echo "----------------------------------------------------------------------------"
EVENT_BRIDGE_ARN=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/EventBusArn" | jq .Parameter.Value | sed -e "s/\"//g")
HOSTED_ZONE_ID=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/HostedZoneId" | jq .Parameter.Value | sed -e "s/\"//g")
RDS_HOST=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/RdsHost" | jq .Parameter.Value | sed -e "s/\"//g")

echo "Fetching resource ARNs needed for SAM template.yaml ..."
echo "----------------------------------------------------------------------------"
# WARNING: This script relies heavily on Sceptre-CF naming conventions
#          changes to resource names may invalidate this script!
for resource in `aws resource-groups search-resources --resource-query file://$TAG_QUERY | jq .ResourceIdentifiers[].ResourceArn`; do
  # echo $resource

  if [[ "$resource" == *"s3privatebucket"* ]]; then
    S3_CF_BUCKET="$(echo $resource | sed -e "s/\"//g" | sed -e "s/$ARN_PREFIX//")"
  fi
  if [[ "$resource" == *"s3cloudfrontbucket"* ]]; then
    S3_BUCKET_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"userpool"* ]]; then
    COGNITO_USER_POOL_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"regional-dynamo"* ]]; then
    DYNAMO_TABLE_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"regional-sqs-SqsQueue"* ]]; then
    SQS_QUEUE_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"sqs-SnsTopicEmail"* ]]; then
    SNS_EMAIL_TOPIC_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"DeadLetterQueue"* ]]; then
    DEAD_LETTER_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
done

# Fetch the Cert and WAF info from the global region us-east-1
for resource in `aws resource-groups search-resources --region us-east-1 --resource-query file://$TAG_QUERY | jq .ResourceIdentifiers[].ResourceArn`; do
  if [[ "$resource" == *"arn:aws:acm"* ]]; then
    CERT_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
  if [[ "$resource" == *"global-waf"* ]]; then
    WAF_ARN="$(echo $resource | sed -e "s/\"//g")"
  fi
done

FAIL=0
if [ -z $EVENT_BRIDGE_ARN ]; then echo "No EventBus found!"; FAIL=1; fi
if [ -z $HOSTED_ZONE_ID ]; then echo "No Hosted Zone Id found!"; FAIL=1; fi
if [ -z $CERT_ARN ]; then echo "No Certificate found!"; FAIL=1; fi
if [ -z $WAF_ARN ]; then echo "No WAF found!"; FAIL=1; fi
if [ -z $S3_CF_BUCKET ]; then echo "No S3 Bucket found for CloudFormation!"; FAIL=1; fi
if [ -z $S3_BUCKET_ARN ]; then echo "No S3 Bucket found for CloudFront!"; FAIL=1; fi
if [ -z $COGNITO_USER_POOL_ARN ]; then echo "No Cognito UserPool found!"; FAIL=1; fi
if [ -z $DYNAMO_TABLE_ARN ]; then echo "No Dynamo Table found!"; FAIL=1; fi
if [ -z $SQS_QUEUE_ARN ]; then echo "No SQS Queue found!"; FAIL=1; fi
if [ -z $DEAD_LETTER_ARN ]; then echo "No SQS Dead Letter Queue found!"; FAIL=1; fi
if [ -z $SNS_EMAIL_TOPIC_ARN ]; then echo "No SNS Topic for Email found!"; FAIL=1; fi
if [ -z $RDS_HOST ]; then echo "No RDS Hostname!"; FAIL=1; fi
# FAIL=1
if [ $FAIL == 1 ]; then exit 1; fi

# There is probably a much more efficient way to do this with arrays in bash
P1="$KEY=Env,$VAL=$1"
P2="$KEY=S3CloudFrontBucketArn,$VAL=$S3_BUCKET_ARN"
P3="$KEY=CognitoUserPoolArn,$VAL=$COGNITO_USER_POOL_ARN"
P4="$KEY=DomainName,$VAL=$2"
P5="$KEY=DynamoTableArn,$VAL=$DYNAMO_TABLE_ARN"
P6="$KEY=SqsQueueArn,$VAL=$SQS_QUEUE_ARN"
P7="$KEY=DeadLetterQueueArn,$VAL=$DEAD_LETTER_ARN"
P8="$KEY=SnsEmailTopicArn,$VAL=$SNS_EMAIL_TOPIC_ARN"
P9="$KEY=CertificateArn,$VAL=$CERT_ARN"
P10="$KEY=WafArn,$VAL=$WAF_ARN"
P11="$KEY=EventBusArn,$VAL=$EVENT_BRIDGE_ARN"
P12="$KEY=HostedZoneId,$VAL=$HOSTED_ZONE_ID"
P13="$KEY=RdsHost,$VAL=$RDS_HOST"

# Build the LambdaLayer if applicable
if [ "$3" == "true" ]; then
  cd ./src/sam/layers
  echo "Building Lambda Layers from $(pwd)..."
  echo "----------------------------------------------------------------------------"
  ./build.sh
  cd ..
else
  cd ./src/sam
fi

echo "Building Lambda Functions from $(pwd)..."
echo "----------------------------------------------------------------------------"
sam build

echo "Deploying Lambdas and API Gateway ..."
echo "----------------------------------------------------------------------------"
sam deploy \
  --config-env $1 \
  --s3-bucket $S3_CF_BUCKET \
  --parameter-overrides "$P1 $P2 $P3 $P4 $P5 $P6 $P7 $P8 $P9 $P10 $P11 $P12 $P13"
echo ""

echo "PLEASE UPDATE YOUR SWAGGER DOCS IF THE API HAS BEEN CHANGED!!!!"
echo "----------------------------------------------------------------------------"
echo "  Swagger/OpenAPI specifications can be found in the src/swagger/ directory."
echo ""
