#!/usr/bin/env bash

set -exu

ROOT_DIR=$PWD

start-bosh -o /usr/local/bosh-deployment/local-dns.yml

source /tmp/local-bosh/director/env

bosh int /tmp/local-bosh/director/creds.yml --path /jumpbox_ssh/private_key > /tmp/jumpbox_ssh_key.pem
chmod 400 /tmp/jumpbox_ssh_key.pem

export BOSH_GW_PRIVATE_KEY="/tmp/jumpbox_ssh_key.pem"
export BOSH_GW_USER="jumpbox"
export BOSH_DIRECTOR_IP="10.245.0.3"
export BOSH_BINARY_PATH="$(which bosh)"
export BOSH_DEPLOYMENT="uaa"

bosh upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-xenial-go_agent

pushd "$ROOT_DIR/uaa-release"
    bosh create-release
    bosh upload-release
popd

export GOPATH="$ROOT_DIR/uaa-release"
export PATH="${GOPATH}/bin:$PATH"

go get github.com/onsi/ginkgo/ginkgo
go install github.com/onsi/ginkgo/ginkgo

cp $ROOT_DIR/uaa-release/src/acceptance_tests/uaa-docker-deployment.yml /tmp/uaa-deployment.yml
bosh -n deploy /tmp/uaa-deployment.yml -o "$ROOT_DIR/uaa-release/src/acceptance_tests/opsfiles/enable-local-uaa.yml" --vars-store=/tmp/uaa-store.json -v system_domain=`hostname --fqdn`

pushd "$GOPATH/src/acceptance_tests"
   ginkgo -v -keepGoing -randomizeAllSpecs -randomizeSuites -race -r .
popd