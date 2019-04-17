# UAA Acceptance tests

# Run locally

Do NOT use docker for mac, it doesn't seem to be working
with the acceptance tests at the moment.

```
export MACHINE_STORAGE_PATH=<path to HDD>/.docker/machine # e.g /Volumes/Blythdale HDD
# You can also set it to a SSD disk but it does take quite a bit of space

docker-machine create uaa-release-acceptance-tests \
--virtualbox-cpu-count 4 \
--virtualbox-disk-size 50000 \
--virtualbox-memory "4096"

eval "$(docker-machine env uaa-release-acceptance-tests)"
```


```
./scripts/run-locally.sh
# You are placed in a container that can connect to a bosh director
# make changes to the acceptance tests go file
ginkgo -v --progress --trace -r .
```
