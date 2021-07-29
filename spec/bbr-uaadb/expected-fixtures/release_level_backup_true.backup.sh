#!/usr/bin/env bash
set -e

JOB_PATH="/var/vcap/jobs/bbr-uaadb"

# Anything placed in the BBR_ARTIFACT_DIRECTORY by the backup script will be available to the restore script at restore time.
# The BBR CLI is responsible for setting the BBR_ARTIFACT_DIRECTORY
BBR_ARTIFACT_FILE_PATH="${BBR_ARTIFACT_DIRECTORY}/uaadb-artifact-file"
CONFIG_PATH="${JOB_PATH}/config/config.json"


"/var/vcap/jobs/database-backup-restorer/bin/backup" --config "${CONFIG_PATH}" --artifact-file "${BBR_ARTIFACT_FILE_PATH}"

