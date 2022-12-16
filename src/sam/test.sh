echo "Building the Lambda Layer ..."
cd layers
./build.sh
echo ""

cd ..

echo "Running Rubocop checks ..."
bundle exec rubocop -a layers/ruby/lib
bundle exec rubocop -a functions
bundle exec rubocop -a spec
echo ""

echo "Running RSpec tests ..."
bundle exec rspec spec
echo ""

echo "DONE"