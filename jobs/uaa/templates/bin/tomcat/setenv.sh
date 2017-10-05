#!/bin/bash

if [ -f /var/vcap/data/uaa/bbr_limited_mode.lock ]; then
  export JAVA_OPTS="-Duaa.limitedFunctionality.enabled=true $JAVA_OPTS"
fi
