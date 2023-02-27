#!/bin/bash

cd src/sam/layers
# We need to rebuild the LambdaLayer in order for changes to be picked up
echo "Building Lambda Layers ..."
./build.sh test
echo ""

cd ..

echo "Bundling with test dependencies ..."
bundle config set --local without ''
bundle install
echo ""
echo ""

echo "Running Rubocop checks ..."
bundle exec rubocop -a layers/ruby/lib
bundle exec rubocop -a functions
bundle exec rubocop -a spec
echo ""
echo ""

echo "Running RSpec tests ..."
bundle exec rspec spec/
echo ""
echo ""

echo "Re-bundling to remove test dependencies ..."
bundle config set --local without 'test'
bundle install
cd layers
./build.sh
cd ../../..
echo ""
echo "DONE"