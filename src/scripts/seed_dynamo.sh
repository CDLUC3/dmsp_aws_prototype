
if [ $# -ne 3 ]; then
  echo 'Wrong number of arguments. Expecting 4:'
  echo '  - The `env` for for the Dynamo Table (e.g. dev)'
  echo '  - The Name of the external system (e.g. Foo)'
  echo '  - The Domain of the external system (e.g. example.com)'
  exit 1
fi

KEY=$(echo $2 | tr '[:upper:]' '[:lower:]')
SSM_PATH_DYNAMO="/uc3/dmp/hub/$1/DynamoTableName"
SSM_PATH_EMAIL="/uc3/dmp/hub/$1/AdminEmail"

echo "Looking for Dynamo Table name at $SSM_PATH_DYNAMO"
echo "----------------------------------------------------------------------------"
DYNAMO_TABLE=$(echo `aws ssm get-parameter --name $SSM_PATH_DYNAMO | jq .Parameter.Value | sed -e "s/\"//g"`)
ADMIN_EMAIL=$(echo `aws ssm get-parameter --name $SSM_PATH_EMAIL | jq .Parameter.Value | sed -e "s/\"//g"`)

if [ -z $DYNAMO_TABLE ]; then echo "No Dynamo Table name found in SSM!"; exit 1; fi

echo "Seeding $DYNAMO_TABLE ..."
echo "----------------------------------------------------------------------------"
echo "Creating Provenance item for $2 -> {\"PK\": \"PROVENANCE#$KEY\", \"SK\": \"PROFILE\"}"
# Insert the Provenance record for the DMPTool application
aws dynamodb put-item --table-name $DYNAMO_TABLE  \
    --item \
        "{\"PK\":{\"S\":\"PROVENANCE#$KEY\"},\"SK\":{\"S\":\"PROFILE\"},\"contact\":{\"M\":{\"email\":{\"S\":\"$ADMIN_EMAIL\"},\"name\":{\"S\":\"Administrator\"}}},\"description\":{\"S\":\"The $2 $1 system\"},\"downloadUri\":{\"S\":\"https://$3/api/v2/plans/\"},\"homepage\":{\"S\":\"https://$3\"},\"name\":{\"S\":\"$2\"},\"redirectUri\":{\"S\":\"https://$3/callback\"},\"tokenUri\":{\"S\":\"https://$3/oauth/token\"}}"

# Insert the root AUGMENTERS record
echo "Creating Augmenter records -> { \"PK\": \"AUGMENTERS\", \"SK\": \"LIST\" } and { \"PK\": \"AUGMENTERS#datacite\", \"SK\": \"PROFILE\" }"
aws dynamodb put-item --table-name $DYNAMO_TABLE  \
    --item \
      "{\"PK\":{\"S\":\"AUGMENTERS\"},\"SK\":{\"S\":\"LIST\"},\"related_works\":{\"L\":[{\"M\":{\"PK\":{\"S\":\"AUGMENTERS#datacite\"}}}]}}"

# Insert the DataCite Augmenter record
aws dynamodb put-item --table-name $DYNAMO_TABLE  \
    --item \
      "{\"PK\":{\"S\":\"AUGMENTERS#datacite\"},\"SK\":{\"S\":\"PROFILE\"},\"frequency\":{\"S\":\"daily\"},\"last_run\":{\"S\":\"2023-11-01T00:00:34+00:00\"},\"name\":{\"S\":\"DataCite\"},\"trigger\":{\"M\":{\"detail-type\":{\"S\":\"RelatedWorkScan\"},\"resource\":{\"S\":\"event-bridge\"}}}}"

echo ''
echo 'Done.'
echo ''
echo 'Use the Partition and Sort keys listed above to find the new item in the table and ensure all of the information is correct.'
echo 'For an overview of these records, please see: https://github.com/CDLUC3/dmp-hub-cfn/wiki/database#sample-provenance-item'
echo ''
