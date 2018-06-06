#!/bin/bash

set -eux

source /tmp/local-bosh/director/env
export BOSH_ENVIRONMENT="https://10.245.0.3:25555"

bosh upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent

cp /root/uaa-release/src/acceptance_tests/uaa-docker-deployment.yml /tmp/uaa-deployment.yml
cp /root/uaa-release/scripts/refresh-uaa-deployment.sh /usr/local/bin/refresh

pushd "/root/uaa-release"
    bosh reset-release
    bosh create-release --force
    bosh upload-release
popd

export GOPATH="/root/uaa-release"
export PATH="${GOPATH}/bin:$PATH"
go get github.com/onsi/ginkgo/ginkgo
go install github.com/onsi/ginkgo/ginkgo


bosh -n deploy -d uaa /tmp/uaa-deployment.yml -o "/root/uaa-release/src/acceptance_tests/opsfiles/enable-local-uaa.yml" \
--vars-store=/tmp/uaa-store.json -v system_domain=`hostname --fqdn`


export BOSH_GW_PRIVATE_KEY="/tmp/jumpbox_ssh_key.pem"
export BOSH_GW_USER="jumpbox"
export BOSH_DIRECTOR_IP="10.245.0.3"
export BOSH_BINARY_PATH="$(which bosh)"
export BOSH_DEPLOYMENT="uaa"


cd /root/uaa-release
echo "feel free to run ginkgo -r ."
echo "run refresh after test runs to restore uaa to a good deployment"
bash