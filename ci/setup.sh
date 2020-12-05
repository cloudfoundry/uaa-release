#!/usr/bin/env bash

set -eo pipefail

RELEASE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

pushd "${RELEASE_DIR}" > /dev/null

team="$(    bosh int ci/settings.yml --path /meta/team)"
pipeline="$(bosh int ci/settings.yml --path /meta/pipeline)"

credhub set -n "/concourse/${team}/git-commit-email"    -t value -v "$(bosh int ci/secrets.yml --path /git_user_email)"
credhub set -n "/concourse/${team}/git-commit-name"     -t value -v "$(bosh int ci/config.yml  --path /git_user_name)"
credhub set -n "/concourse/${team}/aws-access-key"      -t value -v "$(bosh int ci/secrets.yml --path /s3_access_key_id)"
credhub set -n "/concourse/${team}/aws-secret-key"      -t value -v "$(bosh int ci/secrets.yml --path /s3_secret_access_key)"

credhub set -n "/concourse/${team}/slack-username"            -t value -v "gk-concourse-ninja"
credhub set -n "/concourse/${team}/slack-icon-url"            -t value -v "https://cl.ly/2F421Y300u07/concourse-logo-blue-transparent.png"
credhub set -n "/concourse/${team}/${pipeline}/slack-webhook" -t value -v "$(bosh int ci/secrets.yml --path /slack_webhook)"

credhub set -n "/concourse/${team}/github-access-token" -t value -v "$(bosh int ci/secrets.yml --path /github_access_token)"
credhub set -n "/concourse/${team}/github-private-key"  -t value -v "$(bosh int ci/secrets.yml --path /github_private_key)"

credhub set -n "/concourse/${team}/bosh-lite-environment"   -t value -v "$(bosh int ci/secrets.yml --path /bosh-lite-environment)"
credhub set -n "/concourse/${team}/bosh-lite-ca-cert"       -t value -v "$(bosh int ci/secrets.yml --path /bosh-lite-ca-cert)"
credhub set -n "/concourse/${team}/bosh-lite-client"        -t value -v "$(bosh int ci/secrets.yml --path /bosh-lite-client)"
credhub set -n "/concourse/${team}/bosh-lite-client-secret" -t value -v "$(bosh int ci/secrets.yml --path /bosh-lite-client-secret)"

# To delete all:
#
#     credhub find | awk '/concourse/{print $3}' | xargs -n 1 credhub delete -n
# or
#     credhub find --path "/concourse/main" --output-json | jq -r ".credentials[].name" | xargs -n 1 credhub delete -n

popd > /dev/null
