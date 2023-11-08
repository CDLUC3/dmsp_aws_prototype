
if [ $# -ne 1 ]; then
  echo 'Expected the env to be passed as an argument! (e.g. `./build.sh dev`)'
  exit 1
fi

export S3_BUCKET=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3PrivateBucketId" | jq .Parameter.Value | sed -e "s/\"//g")

if [ -z $S3_BUCKET ]; then echo "No S3 Bucket found!"; exit 1; fi

# Upload the Zip to S3
aws s3 rm "s3://$S3_BUCKET/lambda-publisher.zip"
