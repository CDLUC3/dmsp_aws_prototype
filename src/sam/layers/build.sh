#!/bin/bash
mkdir -p "$SAM_BUILD_DIR/ruby"

echo "    Bundling gems into $SAM_BUILD_DIR/ruby ..."
bundle config path $SAM_BUILD_DIR
bundle config --local with ''
bundle config --local without 'test'
bundle install --quiet

echo "    Transferring gems to Lambda dir ..."
mkdir -p "$SAM_BUILD_DIR/ruby/gems"
cp -rf "$SAM_BUILD_DIR/ruby/2.7.0/gems" "$SAM_BUILD_DIR/ruby/gems/2.7.0"
rm -rf "$SAM_BUILD_DIR/ruby/2.7.0"

echo "    Generating MD5 hash"
find "$$SAM_BUILD_DIR/ruby/gems/2.7.0/" -type f -exec md5sum {} + > md5.txt
