# Uc3DmpRds gem

Helper class for accessing the DMPTool database

This gem uses the uc3-dmp-api-core gem to access the AWS to fetch your DB credentials

It also uses mysql2 which means that when using this gem with a Lambda function, that function will need to reside within a Docker container that has installed mysql developer tools!
