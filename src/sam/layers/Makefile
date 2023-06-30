build-LambdaLayer:
	mkdir -p "$(ARTIFACTS_DIR)/ruby"

	echo "    Bundling gems into $(ARTIFACTS_DIR) ..."
	bundle config path "$(ARTIFACTS_DIR)"
	bundle config --local with ''
	bundle config --local without 'test'
	bundle install

	mkdir -p "$(ARTIFACTS_DIR)/ruby/gems"
	cp -rf "$(ARTIFACTS_DIR)/ruby/2.7.0/gems" "$(ARTIFACTS_DIR)/ruby/gems/2.7.0"
	rm -rf "$(ARTIFACTS_DIR)/ruby/2.7.0"
