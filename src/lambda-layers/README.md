# Lambda Layers

All of our Lambda Functions are managed via Sceptre and individual `build_deploy.sh` scripts.

Each of the sub directories in this folder categories our LambdaLayer code by the way in which the Lambda Functions it supports are triggered. For example the LambdaLayer in the `dynamo/` directory supports Lambda Functions that are triggered by DynamoDB Table Stream events

Each of the layers will be automatically built and deployed the first time you run: `sceptre create [env]/regional/lambda-layers/[category].yaml`

After the Cloud Formation stack has been created, you can simply run: `.build_deploy.sh [env]` in the specific layer's directory to re-build and then deploy your updates to the S3 bucket. The S3 bucket is configured to execute the LambdaPublisher function when a new version of the Zip is uploaded. That function will automatically deploy the Layer.

If you need to add or remove a layer, you can delete the resource from S3 and then run: `sceptre update [env]/regional/lambda-layers/[category].yaml`

If you need to upgrade the Lambda Runtime to a newer version of Ruby, you will need to update the Ruby version in the `build_deploy.sh` script in whichever category you are upgrading. You will also need to then update the Sceptre config as well `./config/[env]/regional/lambda-layers/[category].yaml`. Once those files are up to date, re-build the layers as described above and then run a Sceptre update.

Note that it may be necessary to re-publish any Lambda Functions that make use of you layer after you redeploy!
