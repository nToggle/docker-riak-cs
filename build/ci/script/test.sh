#!/usr/bin/env bash

# Setup error trapping.

set -e
trap 'echo "Error occured on line $LINENO." && exit 1' ERR

source "./build/ci/script/version.sh"

function check_startup() {
    local tries=0
    local maxTries=60

    #docker exec -it 'riak-cs' riak-admin wait-for-service riak_kv
    echo -n "Waiting for Riak CS"

    until (docker logs riak-cs | grep "Finished creating CS buckets" > /dev/null) || ((++tries >= maxTries)) ; do
        echo -n "."
        sleep 1
    done

    if ((tries >= maxTries)); then
        echo -e "\nTime out waiting for Riak CS after ${tries} attempts…"
        exit 1
    fi

    echo " OK!"
}

if command -v docker-machine 2>/dev/null; then
    DOCKER_IP=$(docker-machine ip ${DOCKER_MACHINE_NAME})
else
    DOCKER_IP=127.0.0.1
fi

# Run riak cs and sleep for 45 seconds allowing it to initialise.
echo -n "Starting riak-cs container using docker at $DOCKER_IP"
docker run \
    --detach \
    --env 'RIAK_CS_BUCKETS=foo,bar,baz' \
    --name 'riak-cs' \
    --publish '8080:8080' \
    quay.io/ntoggle/riak-cs:$IMAGE_VERSION > /dev/null
echo ' OK!'

check_startup

# Print docker logs and check that we have credentials and buckets succesfully setup.

LOGS=$(docker logs riak-cs)
echo "$LOGS"

# First check that container is running.

echo -n 'Checking if riak-cs container running…'
if [ $(docker inspect --format '{{ .State.Running }}' riak-cs) == 'true' ]; then
echo ' OK!'; else echo ' Fail!'; exit 1; fi;

access_key=$(echo "$LOGS" | pcregrep -o '^\h*Access key:\h*\K(.{20})$' || echo '')
secret_key=$(echo "$LOGS" | pcregrep -o '^\h*Secret key:\h*\K(.{40})$' || echo '')

echo -n 'Checking if container logs contain admin credentials…'
if [ -n "$access_key" ] && [ -n "$secret_key" ]; then
echo ' OK!'; else echo ' Fail!'; exit 1; fi;

echo -n 'Checking if container logs contain foo bucket success status…'
if echo "$LOGS" | pcregrep -q '^foo… OK!$'; then
echo ' OK!'; else echo ' Fail!'; exit 1; fi;

echo -n 'Checking if container logs contain bar bucket success status…'
if echo "$LOGS" | pcregrep -q '^bar… OK!$'; then
echo ' OK!'; else echo ' Fail!'; exit 1; fi;

echo -n 'Checking if container logs contain baz bucket success status…'
if echo "$LOGS" | pcregrep -q '^baz… OK!$'; then
echo ' OK!'; else echo ' Fail!'; exit 1; fi;

# Now lets use s3cmd to actually connect to our riak cs service and run some tests on it.

cat <<-EOL > /tmp/configuration
	[default]
	access_key = $access_key
	host_base = s3.amazonaws.com
	host_bucket = %(bucket)s.s3.amazonaws.com
	proxy_host = $DOCKER_IP
	proxy_port = 8080
	secret_key = $secret_key
	signature_v2 = True
	use_https = False
EOL

echo 'Listing buckets with s3cmd:'
s3cmd --config '/tmp/configuration' ls

echo 'Putting file into foo bucket and list it with s3cmd:'
s3cmd --config '/tmp/configuration' put 'README.md' 's3://foo'
s3cmd --config '/tmp/configuration' ls 's3://foo'

echo 'Copying file from foo bucket into bar bucket and list it with s3cmd:'
s3cmd --config '/tmp/configuration' cp 's3://foo/README.md' 's3://bar/README.md'
s3cmd --config '/tmp/configuration' ls 's3://bar'

echo 'Remove file from bar bucket and list it with s3cmd:'
s3cmd --config '/tmp/configuration' del 's3://bar/README.md'
s3cmd --config '/tmp/configuration' ls 's3://bar'

echo 'Remove bar bucket and list all buckets with s3cmd:'
s3cmd --config '/tmp/configuration' rb 's3://bar'
s3cmd --config '/tmp/configuration' ls

docker kill riak-cs || docker rm riak-cs || true
