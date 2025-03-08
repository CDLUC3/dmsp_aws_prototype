
# Creating a new environment stack

## SSM variable setup

You need to initialize the following global variables in SSM:
- `aws ssm put-parameter --name /uc3/dmp/HostedZoneId --value [HOSTED_ZONE_ID] --type String`

Note we explicitly do NOT use the "overwrite" argument for global variables to ensure we do not accidentally overwrite values that may have already been initialized.

You need to initialize the following env specific variables in SSM:
- `aws ssm put-parameter --name /uc3/dmp/tool/[ENV]/DbPassword --value [PASSWORD] --type SecureString --overwrite`
- `aws ssm put-parameter --name /uc3/dmp/tool/[ENV]/DefaultAffiliationId --value [ROR ID] --type String --overwrite`

## Run Sceptre

- ecr
- route53
- ecs-cluster
