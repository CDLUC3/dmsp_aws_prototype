export RUBY_VERSION=3.2.2
export TARGET_RUBY_GEM_DIR=3.2.0

build-LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/ruby"

	echo "    Using Ruby version $(RUBY_VERSION)"
	echo "    Bundling gems into $(ARTIFACTS_DIR) ..."
	bundle config path "$(ARTIFACTS_DIR)"
	bundle lock --add-platform x86_64-linux
	bundle config --local with ''
	bundle config --local without 'test'
	bundle install

	mkdir -p "$(ARTIFACTS_DIR)/ruby/gems"
	cp -rf "$(ARTIFACTS_DIR)/ruby/$(TARGET_RUBY_GEM_DIR)/gems" "$(ARTIFACTS_DIR)/ruby/gems/$(TARGET_RUBY_GEM_DIR)"
	rm -rf "$(ARTIFACTS_DIR)/ruby/$(TARGET_RUBY_GEM_DIR)"
