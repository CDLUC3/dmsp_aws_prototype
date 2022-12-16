# Upload the GraphQL schema to S3
S3_BUCKET=$(aws ssm get-parameter --name '/uc3/dmp/hub/dev/S3BucketUri' --query "Parameter.Value" --output text)
aws s3 cp ./schema.graphql s3://$S3_BUCKET/schema.graphql

# TODO: See if this can be managed by SAM
# Build the Layer
cd layers/ && ./build.sh
cd ..

# Run the standard SAM build
sam build
