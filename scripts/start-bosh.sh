#!/bin/bash

start-bosh -o /usr/local/bosh-deployment/local-dns.yml
echo 'start-bosh has finished starting...'

sleep infinity