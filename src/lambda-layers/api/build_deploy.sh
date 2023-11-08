#!/bin/bash

if [ $# -ne 1 ]; then
  echo 'Expected the env to be passed as an argument! (e.g. `./build_deploy.sh dev`)'
  exit 1
fi

export RUBY_VERSION="3.2.2"
export TARGET_RUBY_GEM_DIR="3.2.0"

# Call the build_deploy.sh script with the appropriate args
../build_deploy.sh $1 api
