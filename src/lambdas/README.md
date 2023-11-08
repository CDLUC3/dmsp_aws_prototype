# Lambda Functions

All of our Lambda Functions are managed via Sceptre and individual `build_deploy.sh` scripts.

## LambdaPublisher Function

The LambdaPublisher function monitors the Private S3 bucket for new objects that have been uploaded to the `lambdas/` key prefix (directory). It will detect both LambdaLayers and LambdaFunctions and ensure that they are deployed.

This Lambda replicates the functionality of the `aws sam deploy` command.

## Other Functions

Each of the other sub directories in this folder are categories relating to the primary method that is used to trigger the lambda functions. For example the Functions in the `dynamo/` directory are triggered by DyanmoDb Table Stream events. Note that even though the functions reside in a specific folder, they may also be triggered in other ways (e.g. a scheduled EventBridge rule). The folders represent their primary use case.

Each of the layers will be automatically built and deployed the first time you run: `sceptre create [env]/regional/lambdas/[category]/[function].yaml`

After the Cloud Formation stack has been created, you can simply run: `.build_deploy.sh [env]` for the specific function's directory to re-build and then deploy your updates to the S3 bucket. The S3 bucket is configured to execute the LambdaPublisher function when a new version of the Zip is uploaded. That function will automatically deploy the changes.

If you need to add or remove a layer, you can delete the resource from S3 and then run: `sceptre update [env]/regional/lambdas/[category]/[function].yaml`

If you need to upgrade the Lambda Runtime to a newer version of Ruby, you will need to update the Ruby version in the `build_deploy.sh` script in whichever category you are upgrading. You will also need to then update the Sceptre config as well `./config/[env]/regional/lambdas/[category]/[function].yaml`. Once those files are up to date, re-build the layers as described above and then run a Sceptre update.

Note that it may be necessary to re-publish any Lambda Functions that make use of you layer after you redeploy!
