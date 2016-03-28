#!/usr/bin/env bash

# Setup error trapping.

set -e
trap 'echo "Error occured on line $LINENO." && exit 1' ERR

# Build docker image.
source "./build/ci/script/version.sh"
docker build --tag "quay.io/ntoggle/riak-cs:$IMAGE_VERSION" "./src"
