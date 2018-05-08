#!/bin/bash

set -xeu

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

docker run \
--link container-running-dockerd \
-it \
-v ~/workspace/uaa-release/:/root/uaa-release \
-v container-running-dockerd-tmp:/tmp/ bosh/main-bosh-docker \
/root/uaa-release/scripts/test-runner.sh

