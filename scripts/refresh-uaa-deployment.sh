#!/bin/bash

set -xeu

bosh -n deld --force -d uaa

cp /root/uaa-release/src/acceptance_tests/uaa-docker-deployment.yml /tmp/uaa-deployment.yml

bosh -n deploy --no-redact \
  /tmp/uaa-deployment.yml \
  -o "/root/uaa-release/src/acceptance_tests/opsfiles/enable-local-uaa.yml" \
  --vars-store=/tmp/uaa-store.json -v system_domain=`hostname --fqdn`
