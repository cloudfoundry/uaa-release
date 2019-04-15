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
        --virtualbox-disk-size="90000" ${DOCKER_HOST_VM_NAME}
fi

eval $(docker-machine env ${DOCKER_HOST_VM_NAME})

if [[ ! $(docker ps --filter name=container-running-dockerd -q) ]]; then
    docker volume rm -f container-running-dockerd-tmp
    docker volume create container-running-dockerd-tmp

    docker run \
        --name=container-running-dockerd \
        -d -t --privileged \
        -v ~/workspace/uaa-release/:/root/uaa-release \
        -v container-running-dockerd-tmp:/tmp/ \
        bosh/main-bosh-docker \
        /root/uaa-release/scripts/start-bosh.sh

    set +x

    function test_query() {
        docker logs container-running-dockerd | grep 'start-bosh has finished starting...'
    }

    docker logs container-running-dockerd -f &

    until test_query; do
        sleep 2
    done

    set -x
else
    echo "The container running the BOSH Director still exists, so using it"
fi

set +e
docker run \
    --link container-running-dockerd \
    -it \
    -v ~/workspace/uaa-release/:/root/uaa-release \
    -v container-running-dockerd-tmp:/tmp/ bosh/main-bosh-docker \
    /root/uaa-release/scripts/test-runner.sh
set -e

echo "Want to run again with the same BOSH Director? Just run this script (run-locally.sh) again."
echo "Otherwise, when you are finished, use 'docker-machine rm ${DOCKER_HOST_VM_NAME}' to delete everything"
