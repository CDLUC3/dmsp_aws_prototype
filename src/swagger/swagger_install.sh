#!/bin/bash

echo ''
echo '========================='
echo 'SWAGGER API DOCUMENTATION'
echo '========================='
echo ''

TAG_QUERY='aws_tag_query.json'
S3_ARN_PREFIX='arn:aws:s3:::'
API_ARN_PREFIX='arn:aws:apigateway:us-west-2::\/restapis\/'
SPEC_FILE='api-docs.json'

if [ $# -ne 2 ]; then
  echo 'Wrong number of arguments. Expecting 2: then environment and the swagger version/release (e.g. `swagger_install.sh dev 4.16.1`)'
  exit 1
fi

echo "Fetching identifiers from SSM ..."
echo "----------------------------------------------------------------------------"
CF_DISTRO_ID=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/CloudFrontDistroId" --region us-east-1 | jq .Parameter.Value | sed -e "s/\"//g")

echo "Fetching resource ARNs needed for SAM template.yaml ..."
echo "----------------------------------------------------------------------------"
# WARNING: This script relies heavily on Sceptre-CF naming conventions
#          changes to resource names may invalidate this script!
for resource in `aws resource-groups search-resources --resource-query file://$TAG_QUERY | jq .ResourceIdentifiers[].ResourceArn`; do
  # echo $resource
  if [[ "$resource" == *"s3cloudfrontbucket"* ]]; then
    S3_CLOUDFRONT_BUCKET="$(echo $resource | sed -e "s/\"//g" | sed -e "s/$S3_ARN_PREFIX//")"
  fi
  if [[ "$resource" == *"s3privatebucket"* ]]; then
    S3_CLOUDFORMATION_BUCKET="$(echo $resource | sed -e "s/\"//g" | sed -e "s/$S3_ARN_PREFIX//")"
  fi
  if [[ "$resource" == *"/restapis/"* ]]; then
    REST_API="$(echo $resource | sed -e "s/\"//g" | sed -e "s/$API_ARN_PREFIX//")"
  fi
done
if [ -z $S3_CLOUDFRONT_BUCKET ]; then echo "No S3 Bucket found!"; FAIL=1; fi
if [ -z $S3_CLOUDFORMATION_BUCKET ]; then echo "No S3 Bucket found!"; FAIL=1; fi
if [ -z $REST_API ]; then echo "No S3 Bucket found!"; FAIL=1; fi
if [ -z $CF_DISTRO_ID ]; then echo "No S3 Bucket found!"; FAIL=1; fi
# FAIL=1
if [ $FAIL == 1 ]; then exit 1; fi
echo ""

echo "Syncing Swagger JSON Spec file with $S3_CLOUDFORMATION_BUCKET ..."
echo "----------------------------------------------------------------------------"
aws s3 cp "src/swagger/$SPEC_FILE" "s3://$S3_CLOUDFORMATION_BUCKET/"
echo ""

SWAGGER_DIST_DIR="src/swagger/swagger-ui-$2/dist/"
if [ ! -d $SWAGGER_DIST_DIR ]; then
  echo "Downloading Swagger $2 ..."
  echo "----------------------------------------------------------------------------"
  wget "https://github.com/swagger-api/swagger-ui/archive/v$2.tar.gz" -P src/swagger/
  tar -zxvf "src/swagger/v$2.tar.gz" -C src/swagger/
  rm -rf src/swagger/*.gz
else
  echo "Swagger $2 is already downloaded."
  echo "----------------------------------------------------------------------------"
fi
echo ""

# echo "Fetch API documentation from Rest API - $REST_API ..."
echo "Setting up Swagger openapi specification ..."
echo "----------------------------------------------------------------------------"
mkdir "$SWAGGER_DIST_DIR/docs"
cp src/swagger/v0-api-docs.json $SWAGGER_DIST_DIR/docs-list.json
cp src/swagger/v0-openapi-spec.json $SWAGGER_DIST_DIR/docs
cp src/swagger/assets/*.* $SWAGGER_DIST_DIR

echo "Syncing Swagger $2 distribution with $S3_CLOUDFRONT_BUCKET/api-docs/ ..."
echo "----------------------------------------------------------------------------"
mv "$SWAGGER_DIST_DIR/index.html" "$SWAGGER_DIST_DIR/index.html.bak"
cp "src/swagger/default_index.html" "$SWAGGER_DIST_DIR/index.html"
aws s3 sync $SWAGGER_DIST_DIR "s3://$S3_CLOUDFRONT_BUCKET/api-docs/"
echo ""

echo "Clearing CloudFront cache for the /api-docs directory"
echo "----------------------------------------------------------------------------"
aws cloudfront create-invalidation --distribution-id $CF_DISTRO_ID --paths "/api-docs/*" --region us-east-1
echo ""

echo "DONE"
