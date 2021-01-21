#!/bin/bash

# start the UAA
/var/vcap/bosh/bin/monit start uaa
/var/vcap/jobs/uaa/bin/post-start
