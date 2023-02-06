#!/bin/bash

echo "Fetching resources tagged with [uc3 dmp hub dev] in the global region (us-east-1) ..."
aws resource-groups search-resources --region us-east-1 --resource-query file://aws_tag_query.json

echo "Fetching resources tagged with [uc3 dmp hub dev] in the default region (us-west-2) ..."
aws resource-groups search-resources --resource-query file://aws_tag_query.json
