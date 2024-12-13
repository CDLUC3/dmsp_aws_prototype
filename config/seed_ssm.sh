# SSM Parameters required by these Sceptre config files.
# ----------------------------------------------------------

# Run these once per account
aws ssm put-parameter --name /uc3/dmp/HostedZoneId --value MyHostedZoneId --type String --overwrite
aws ssm put-parameter --name /uc3/dmp/tool/DefaultAffiliationId --value RorId --type String --overwrite
aws ssm put-parameter --name /uc3/dmp/tool/HelpdeskEmail --value MyEmail --type String --overwrite

# Run these for each environment
aws ssm put-parameter --name /uc3/dmp/tool/dev/DbPassword --value MyRdsDbPassword --type SecureString --overwrite
aws ssm put-parameter --name /uc3/dmp/tool/dev/CacheHashSecret --value MyCacheSecret --type SecureString --overwrite
aws ssm put-parameter --name /uc3/dmp/tool/dev/JWTSecret --value MyJWTSecret --type SecureString --overwrite
aws ssm put-parameter --name /uc3/dmp/tool/dev/JWTRefreshSecret --value MyRefreshSecret --type SecureString --overwrite
