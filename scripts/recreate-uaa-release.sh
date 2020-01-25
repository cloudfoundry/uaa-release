#!/bin/bash

set -xeu

pushd /root/uaa-release
    mkdir -p tmp
    UAA_VERSION=0.0.0 bosh create-release --force --tarball=tmp/uaa-dev-release.tgz
    bosh upload-release tmp/uaa-dev-release.tgz
popd
