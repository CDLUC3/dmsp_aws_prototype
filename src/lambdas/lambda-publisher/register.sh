
if [ $# -ne 1 ]; then
  echo 'Expected the env to be passed as an argument! (e.g. `./build.sh dev`)'
  exit 1
fi

export S3_BUCKET=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3PrivateBucketId" | jq .Parameter.Value | sed -e "s/\"//g")
export LAMBDA_FUNCTION=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3LambdaPublisherArn" | jq .Parameter.Value | sed -e "s/\"//g")
if [ -z $S3_BUCKET ]; then echo "No S3 Bucket found!"; exit 1; fi
if [ -z $LAMBDA_FUNCTION ]; then echo "Lambda Function ARn not in SSM! Has it been created?"; exit 1; fi

# Create the NotificationConfiguration JSON
export JSON="{\"LambdaFunctionConfigurations\":[{\"Id\":\"PublishLambdas\",\"LambdaFunctionArn\":\"$LAMBDA_FUNCTION\",\"Events\":[\"s3:ObjectCreated:Put\"],\"Filter\":{\"Key\":{\"FilterRules\":[{\"Name\":\"prefix\",\"Value\":\"lambdas/\"},{\"Name\":\"suffix\",\"Value\":\".zip\"}]}}}]}"

aws s3api put-bucket-notification-configuration --bucket $S3_BUCKET --notification-configuration $JSON
