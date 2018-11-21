#!/bin/bash

set -x

tlscacert=$(find /tmp -name "ca.pem")
tlscert=$(find /tmp -name "cert.pem")
tlskey=$(find /tmp -name "key.pem")

docker --host tcp://container-running-dockerd:4243 \
--tlsverify=false \
--tlscacert=$tlscacert \
--tlscert=$tlscert \
--tlskey=$tlskey \
run \
-v /root/uaa-release:/root/uaa-release \
-v /tmp/:/tmp/ \
--add-host docker-director:10.245.0.3 \
--network=director_network -t -i bosh/main-bosh-docker \
/root/uaa-release/scripts/configure-test-runner.sh