#!/bin/bash

bosh -n deld --force -d uaa

bosh -n deploy \
/tmp/uaa-deployment.yml \
-o "/root/uaa-release/src/acceptance_tests/opsfiles/enable-local-uaa.yml" \
--vars-store=/tmp/uaa-store.json -v system_domain=`hostname --fqdn`