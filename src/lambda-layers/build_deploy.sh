#!/bin/bash

if [ $# -ne 2 ]; then
  echo 'Expected the env and layer name to be passed as arguments! (e.g. `./build_deploy.sh dev eventbridge`)'
  exit 1
fi
if [ -z $RUBY_VERSION ]; then echo "No RUBY_VERSION and or TARGET_RUBY_GEM_DIR variables set!"; exit 1; fi

# Structure the LambdaLayerName Tag as `env-name`. This will be used by the LambdaPublisher Lambda Function
# to auto deploy the Layer once it is uploaded to S3. The `name` should match the suffix of the Layer Name.
#   E.g. if the Layer name is `uc3-dmp-hub-dev-lambda-layer-foo`, then the name should be `foo`
export LAYER_NAME="$1-$2"

export S3_BUCKET=$(aws ssm get-parameter --name "/uc3/dmp/hub/$1/S3PrivateBucketId" | jq .Parameter.Value | sed -e "s/\"//g")
if [ -z $S3_BUCKET ]; then echo "No S3 Bucket found!"; exit 1; fi

# Ensure the correct Ruby environment
rbenv local "$RUBY_VERSION"

# Bundle the Layer
mkdir -p ./build/ruby
bundle config path ./build
bundle lock --add-platform x86_64-linux
bundle config --local with ''
bundle config --local without 'test'
bundle install

# Bundler places them in one folder structure and Lambda wants them in another, so move the bundle
mkdir -p ./build/ruby/gems
cp -rf "./build/ruby/$TARGET_RUBY_GEM_DIR/gems" "./build/ruby/gems/$TARGET_RUBY_GEM_DIR"
rm -rf "./build/ruby/$TARGET_RUBY_GEM_DIR"

# Zip up the build
zip -r "$LAYER_NAME.zip" ./build/ruby

# Upload the Zip to S3 and tag it so the LambdaPublisher Lambda Function can deploy it
aws s3api put-object --bucket $S3_BUCKET \
                     --key "lambdas/layers/$LAYER_NAME.zip" \
                     --body "$LAYER_NAME.zip" \
                     --tagging "Env=$1&NameSuffix=$2"
