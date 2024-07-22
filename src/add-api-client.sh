
if [ $# -ne 3 ]; then
  echo 'Wrong number of arguments. Expecting 2:'
  echo '  - The `env` for the Dynamo Table (e.g. dev)'
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
        "{\"PK\":{\"S\":\"PROVENANCE#$KEY\"},\"SK\":{\"S\":\"PROFILE\"},\"contact\":{\"M\":{\"email\":{\"S\":\"$ADMIN_EMAIL\"},\"name\":{\"S\":\"Administrator\"}}},\"description\":{\"S\":\"The $2 $1 system\"},\"downloadUri\":{\"S\":\"https://$3/api/v2/plans/\"},\"homepage\":{\"S\":\"https://$3\"},\"name\":{\"S\":\"$2\"},\"redirectUri\":{\"S\":\"https://$3/callback\"},\"tokenUri\":{\"S\":\"https://$3/oauth/token\"},\"org_access_level\":{\"S\":\"restricted\"}}"
