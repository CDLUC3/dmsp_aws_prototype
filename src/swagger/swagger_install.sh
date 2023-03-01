#!/bin/bash

TAG_QUERY='aws_tag_query.json'
S3_ARN_PREFIX='arn:aws:s3:::'
API_ARN_PREFIX='arn:aws:apigateway:us-west-2::\/restapis\/'
SPEC_FILE='api-docs.json'

if [ $# -ne 1 ]; then
  echo 'Wrong number of arguments. Expecting 1: the swagger version/release (e.g. `4.16.1`)'
  exit 1
fi

echo "Fetching resource ARNs needed for SAM template.yaml ..."
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
# FAIL=1
if [ $FAIL == 1 ]; then exit 1; fi
echo ""

echo "Syncing Swagger JSON Spec file with $S3_CLOUDFORMATION_BUCKET ..."
aws s3 cp "src/swagger/$SPEC_FILE" "s3://$S3_CLOUDFORMATION_BUCKET/"
echo ""

SWAGGER_DIST_DIR="src/swagger/swagger-ui-$1/dist/"
if [ ! -d $SWAGGER_DIST_DIR ]; then
  echo "Downloading Swagger $1 ..."
  wget "https://github.com/swagger-api/swagger-ui/archive/v$1.tar.gz" -P src/swagger/
  tar -zxvf "src/swagger/v$1.tar.gz" -C src/swagger/
  rm -rf src/swagger/*.gz
else
  echo "Swagger $1 is already downloaded."
fi
echo ""

echo "Fetch API documentation from Rest API - $REST_API ..."
echo "[" > "$SWAGGER_DIST_DIR/docs-list.json"
mkdir "$SWAGGER_DIST_DIR/docs"
aws apigateway get-rest-apis | jq -c -r '.items[]' | while read i;
do
  id=`echo $i | jq -r '.id'`
  name=`echo $i | jq -r '.name'`

  if [[ "$id" == "$REST_API" ]]; then
    for stage in `aws apigateway get-stages --rest-api-id $REST_API | jq -r '.item[].stageName'`;
    do
      echo "    fetching location of docs for Stage: $stage"
      aws apigateway get-export --rest-api-id $REST_API --stage-name "$stage" --export-type swagger "$SWAGGER_DIST_DIR/docs/${stage}-${name}.json"
      echo "{\"url\": \"docs/"${stage}"-"${name}".json\", \"name\": \""${stage}"-"${name}"\"}," >> "$SWAGGER_DIST_DIR/docs-list.json"
    done
  fi
done
truncate -s-2  "$SWAGGER_DIST_DIR/docs-list.json"
echo "]" >> "$SWAGGER_DIST_DIR/docs-list.json"
echo ""

echo "Syncing Swagger $1 distribution with $S3_CLOUDFRONT_BUCKET/api-docs/ ..."
mv "$SWAGGER_DIST_DIR/index.html" "$SWAGGER_DIST_DIR/index.html.bak"
cp "src/swagger/default_index.html" "$SWAGGER_DIST_DIR/index.html"
aws s3 sync $SWAGGER_DIST_DIR "s3://$S3_CLOUDFRONT_BUCKET/api-docs/"
echo ""

echo "DONE"