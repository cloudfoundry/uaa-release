#!/bin/bash

set -euo pipefail

export UAA_VERSION=0.0.0

bosh create-release \
	 --force \
	 --tarball="uaa-dev-release.tgz"
