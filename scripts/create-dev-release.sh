#!/bin/bash

set -euo pipefail

export UAA_VERSION=0.0.0
JAVA_HOME=$(/usr/libexec/java_home -v 17)

export JAVA_HOME

bosh create-release \
	 --force \
	 --tarball="uaa-dev-release-$(date --iso-8601=seconds).tgz"
