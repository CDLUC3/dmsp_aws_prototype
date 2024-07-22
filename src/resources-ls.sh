#!/bin/bash

# Note that as of 2/7/2023, AWS will return stale (deleted) resources here!
#   "Please note that, currently, this is a known issue with Resource Groups Tagging, where the
#    stale/deleted resource tags are still being returned when calling get-resources. I have added
#    your case to the known issue to better prioritize the development."

echo "Fetching resources tagged with [uc3 dmp hub dev] in the global region (us-east-1) ..."
aws resource-groups search-resources --region us-east-1 --resource-query file://aws_tag_query.json

echo "Fetching resources tagged with [uc3 dmp hub dev] in the default region (us-west-2) ..."
aws resource-groups search-resources --resource-query file://aws_tag_query.json
