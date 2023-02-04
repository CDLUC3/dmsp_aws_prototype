#!/bin/bash

echo "Fetching resources tagged with [uc3 dmp hub dev] ..."
aws resource-groups search-resources --resource-query file://aws_tag_query.json
