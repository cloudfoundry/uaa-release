#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

SEVERITY_THRESHOLD=error

find . -name '*.sh' \
	 -print0 \
	| \
	xargs \
		-0 \
		-I{} \
		-n1 \
		-t \
		shellcheck \
		--severity="${SEVERITY_THRESHOLD}" \
		{}
