# Changle Log

### Added
- `redis.yaml` Elasticache template
- `redis-backend.yaml` Sceptre config
- Session Manager policies for `ecs-frontend` and `ecs-backend` so that we can connect to containers
- S3 bucket for use when transferring files between our AWS cloud environ to/from COKI's Google cloud

### Updated
- Updated JWT TTL for `ecs-backend`
- Removed `JwtSecret`from `ecs-frontend`
- Updated the `ecs-backend.yaml` Sceptre config and template to include the Elasticache Host and Port and also a bunch of new bcrypt, crypto, NODE_ENV and jwt ENV variables
- Updated the `ecs-cluster.yaml` so that it has the Redis port and attaches to the Redis Security Group
- Updated the `ecs-backend.yaml` and `ecs-frontend.yaml` to have a minimum of 2 containers
- Updated the `initial_setup.rb` script so that the JWT refresh token secret and Cache hash secret can be specified (updated the Wiki documentation as well)
- Updated the `alb.yaml` with the new refresh, signout and csrf backend endpoints

### Fixed
- Corrected ways that env variables defined in `config/regional/ecs-frontend.yaml` file

## v1.4.4

### Added
- Sceptre config config/dev/regional/dynamo-external-data-table.yaml
- CF template templates/dynamo-external-data-table.yaml

### Updated
- Updated the README to reflect the move of the Lambda, swagger and landing page functionality to the dmsp_api_prototype repo

# v1.4.3

- Offical migration of all Lambda function, Swagger UI and Landing Page files over to the dmsp_api_prototype repository
