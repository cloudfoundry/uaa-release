#!/bin/bash

set -xeu

pushd ~/workspace/uaa-release
    mkdir -p tmp
    bosh create-release --force --tarball=tmp/uaa-dev-release.tgz
popd

DOCKER_HOST_VM_NAME=uaareleaseacceptancetests

if ! docker-machine ls --format "{{.Name}}" | egrep --quiet "^${DOCKER_HOST_VM_NAME}\$" ; then
    # create if it does not already exist, otherwise just use it
    docker-machine create -d virtualbox \
        --virtualbox-cpu-count 2 --virtualbox-memory 4096 \
        --virtualbox-disk-size="50000" ${DOCKER_HOST_VM_NAME}
fi

eval $(docker-machine env ${DOCKER_HOST_VM_NAME})

docker volume rm -f container-running-dockerd-tmp
docker volume create container-running-dockerd-tmp

docker run \
    --name=container-running-dockerd \
    -d -t --privileged \
    -v ~/workspace/uaa-release/:/root/uaa-release \
    -v container-running-dockerd-tmp:/tmp/ \
    bosh/main-bosh-docker \
    /root/uaa-release/scripts/start-bosh.sh

function test_query() {
    docker logs container-running-dockerd | grep 'start-bosh has finished starting...'
}

until test_query; do
    sleep 1
done

set +e
    docker run \
        --link container-running-dockerd \
        -it \
        -v ~/workspace/uaa-release/:/root/uaa-release \
        -v container-running-dockerd-tmp:/tmp/ bosh/main-bosh-docker \
        /root/uaa-release/scripts/test-runner.sh
set -e
echo "When you are finished, use 'docker-machine rm ${DOCKER_HOST_VM_NAME}' to clean up"
