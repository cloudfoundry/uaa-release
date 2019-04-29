#!/bin/bash

set -xeu

pushd /root/uaa-release
    mkdir -p tmp
    bosh create-release --force --tarball=tmp/uaa-dev-release.tgz
    bosh upload-release tmp/uaa-dev-release.tgz
popd
