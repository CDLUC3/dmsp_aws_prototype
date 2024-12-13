if [ $# -ne 1 ]; then
  echo 'Wrong number of arguments. Expecting 1:'
  echo '  - The `branch` we want to deploy (e.g. main, development, etc.)'
  echo '  - Both the backend and frontend MUST have the same branch and should be in a state where that branch can be checked out'
  exit 1
fi

# Fetch the ECR Repository URI from CloudFormation
AWS_REGION=us-west-2
ECR_EXPORT_NAME=dmptool-EcrRepository

ECR_URI=$(aws cloudformation list-exports --query "Exports[?Name=='${ECR_EXPORT_NAME}Uri'].Value" --output text)
ECR_NAME=$(aws cloudformation list-exports --query "Exports[?Name=='${ECR_EXPORT_NAME}Name'].Value" --output text)
SHORT_ECR_URI=$(echo $ECR_URI | cut -d'/' -f1)

echo Logging in to Amazon ECR - ${ECR_URI}
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $SHORT_ECR_URI

BACKEND_TAG_SUFFIX=apollo-latest
FRONTEND_TAG_SUFFIX=nextjs-latest

# Build the backend image
# -------------------------------------------------
echo Building the Apollo server image ...
cd ../dmsp_backend_prototype
git checkout $1

# BACKEND_COMMIT=$(git rev-parse --short HEAD)
BACKEND_TAG=$ECR_NAME:$BACKEND_TAG_SUFFIX

# Install all of the dependencies (including dev so we can compile TS)
npm install --production=false

# Generate all of the GraphQL schema types
npm run generate

# Build the Apollo server which writes to the ./dist dir
npm run build

docker build -f Dockerfile.aws -t $BACKEND_TAG .
docker tag $BACKEND_TAG $SHORT_ECR_URI/$BACKEND_TAG

echo Pushing the Docker images...
docker push $SHORT_ECR_URI/$BACKEND_TAG

# Build the frontend image
# -------------------------------------------------
echo Building the nextJS image ...
cd ../dmsp_frontend_prototype
git checkout $1

FRONTEND_TAG=$ECR_NAME:$FRONTEND_TAG_SUFFIX

# TODO: Using the prod Dockerfile results in a 'missing husky' error. Eventually figure out why and switch
docker build -f Dockerfile.dev -t $FRONTEND_TAG .
docker tag $FRONTEND_TAG $SHORT_ECR_URI/$FRONTEND_TAG

echo Pushing the Docker images...
docker push $SHORT_ECR_URI/$FRONTEND_TAG

# Build the Shibboleth image
# -------------------------------------------------