#!/bin/bash

set -eux

source /tmp/local-bosh/director/env
export BOSH_ENVIRONMENT="https://10.245.0.3:25555"

stemcell_type=warden-boshlite-ubuntu-xenial-go_agent
stemcell_version=170.9
if [[ ! $(bosh stemcells --column=name --column=version |  grep $stemcell_type | fgrep $stemcell_version) ]]; then
    bosh upload-stemcell https://s3.amazonaws.com/bosh-core-stemcells/warden/bosh-stemcell-${stemcell_version}-${stemcell_type}.tgz
else
    echo "stemcell $stemcell_version $stemcell_type already uploaded: skipping upload"
fi

cp /root/uaa-release/src/acceptance_tests/uaa-docker-deployment.yml /tmp/uaa-deployment.yml
cp /root/uaa-release/scripts/refresh-uaa-deployment.sh /usr/local/bin/redeploy

pushd "/root/uaa-release"
    bosh upload-release tmp/uaa-dev-release.tgz
popd

export GOPATH="/root/uaa-release"
export PATH="${GOPATH}/bin:$PATH"
go get github.com/onsi/ginkgo/ginkgo
go install github.com/onsi/ginkgo/ginkgo

set +e # continue if the bosh deploy fails, to allow debugging
bosh -n deploy --no-redact -d uaa /tmp/uaa-deployment.yml \
  -o "/root/uaa-release/src/acceptance_tests/opsfiles/enable-local-uaa.yml" \
  --vars-store=/tmp/uaa-store.json -v system_domain=`hostname --fqdn`
set -e

export BOSH_GW_PRIVATE_KEY="/tmp/jumpbox_ssh_key.pem"
export BOSH_GW_USER="jumpbox"
export BOSH_DIRECTOR_IP="10.245.0.3"
export BOSH_BINARY_PATH="$(which bosh)"
export BOSH_DEPLOYMENT="uaa"

cd /root/uaa-release

set +x

echo
echo "Run 'ginkgo -v --progress --trace -r .' to run acceptance tests"
echo "    - Optionally add '-keepGoing' to keep going after a failure"
echo "Run 'redeploy' to delete and redeploy uaa to restore to a clean deployment"
echo "Run 'exit' when you are finished"

bash
