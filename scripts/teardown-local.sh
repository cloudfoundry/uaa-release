#!/usr/bin/env bash

docker kill $(docker ps -qa)
docker rm -v $(docker ps -qa)
docker volume rm -f container-running-dockerd-tmp
