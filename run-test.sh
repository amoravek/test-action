#!/bin/bash

./scripts/process-downloads.sh \
artifacts.yaml \
vendor-metadata.yaml \
artifactory-user \
artifactory-password \
http://artifactory-base-url \
artifactory-repo \
duser \
dpasswd
