#!/bin/bash

# We need to rebuild the LambdaLayer in order for changes to be picked up
echo "Building Lambda Layers ..."
cd layers
./build.sh test
echo ""
cd ..

echo "Bundling with test dependencies ..."
bundle install --with test

echo "Running Rubocop checks ..."
bundle exec rubocop -a layers/ruby/lib
bundle exec rubocop -a functions
bundle exec rubocop -a spec
echo ""

echo "Running RSpec tests ..."
bundle exec rspec spec
echo ""

echo "Re-bundling to remove test dependencies ..."
bundle install --without test


echo "DONE"