#!/usr/bin/env bash

# Setup error trapping.

set -e
trap 'echo "Error occured on line $LINENO." && exit 1' ERR

# Authenticate with docker and push the latest image.
source "./build/ci/script/version.sh"

docker login -e $DOCKER_EMAIL -u $DOCKER_USER -p $DOCKER_PASS quay.io
docker push quay.io/ntoggle/riak-cs:$IMAGE_VERSION
