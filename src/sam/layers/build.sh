ZIP_NAME="uc3-dmp-hub-lambda-layer.zip"

RUBY_VERSION=2.7.0

# Lambda Layers are imported into the Lambda as /opt/ruby/gems/[Version]
# so we need to bundle and then move them to the appropriate dir
BUNDLER_BUILD_DIR=ruby/$RUBY_VERSION
BUNDLER_GEM_DIR=ruby/$RUBY_VERSION/gems
SAM_GEM_DIR=ruby/gems

# Cleanup
if [ -f Gemfile.lock ]; then rm Gemfile.lock; fi
if [ -f $ZIP_NAME ]; then rm $ZIP_NAME; fi
if [ -d $SAM_GEM_DIR/$RUBY_VERSION ]; then rm -rf $SAM_GEM_DIR/$RUBY_VERSION/**; fi

# Run bundler
if [ -d $BUNDLER_BUILD_DIR ]; then bundle clean; fi
bundle install --without test
cp -r $BUNDLER_GEM_DIR/** $SAM_GEM_DIR/$RUBY_VERSION
rm -rf $BUNDLER_BUILD_DIR

# Create the ZIP artifact
zip -r $ZIP_NAME ruby