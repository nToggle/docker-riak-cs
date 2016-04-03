#!/usr/bin/env bash

# Make sure we are in the same directory as the script and run relevant scripts in that order.

cd $(dirname $0)

#
# @param $1 Riak CS admin key.
# @param $2 Riak CS admin secret.
# @param $3 Riak CS bucket to create.
#
function riak_cs_create_bucket(){
    local key_access=$1
    local key_secret=$2
    local bucket=$3

    # We must use signed requests to make any calls to the service, this apparently isn't very easy. They are in great
    # detail explained in S3 documentation available at the address below. This also looks a little more confusing,
    # because we'd ideally use domain names, but we can't, as we are inside the container. So, we make all calls to
    # local host, any non bucket paths must be appended to the primary url, while bucket always goes in the host header.
    #
    # http://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html
    # http://docs.basho.com/riakcs/latest/references/apis/storage/s3/RiakCS-GET-Bucket/
    # http://docs.basho.com/riakcs/latest/references/apis/storage/s3/RiakCS-PUT-Bucket/
    # http://docs.basho.com/riakcs/latest/tutorials/quick-start-riak-cs/

    echo -n "${bucket}…"

    local date=$(date -R)
    local signature="$(printf "GET\n\n\n${date}\n/${bucket}/" | openssl sha1 -binary -hmac "${key_secret}" | base64)"

    local status_code=$(curl \
        --header "Authorization: AWS ${key_access}:${signature}" \
        --header "Date: ${date}" \
        --header "Host: ${bucket}.s3.amazonaws.com" \
        --insecure \
        --output /dev/null \
        --request GET \
        --silent \
        --write-out '%{http_code}' \
        "http://127.0.0.1:8080")

    if [[ "${status_code}" = '200' ]]; then
        echo ' Already exists!'
    else
        local date=$(date -R)
        local signature="$(printf "PUT\n\n\n${date}\n/${bucket}/" | openssl sha1 -binary -hmac "${key_secret}" | base64)"

        local status_code=$(curl --insecure --silent \
            --request PUT \
            --header "Authorization: AWS ${key_access}:${signature}" \
            --header "Date: ${date}" \
            --header "Host: ${bucket}.s3.amazonaws.com" \
            --output /dev/null \
            --write-out '%{http_code}' \
            "http://127.0.0.1:8080")

        if [ "${status_code}" = '200' ]; then
            echo ' OK!'
        else
            echo ' Failed!'
        fi
    fi
}

#
# @param $1 Command name.
# @param $1 Service name.
#
function basho_service_start() {
    local commandName=$1
    local serviceName=$2
    local tries=0
    local maxTries=5

    echo -n "Starting ${serviceName}…"
    "${commandName}" start

    until (riak ping | grep "pong" > /dev/null) || ((++tries >= maxTries)) ; do
        echo "Waiting for ${serviceName}…"
        sleep 1
    done

    if ((tries >= maxTries)); then
        echo -e "\nCould not start ${serviceName} after ${tries} attempts…"
        exit 1
    fi

    echo " OK!"
}

#
# @param $1 Command name.
# @param $2 Service name.
#
function basho_service_stop() {
    commandName=$1
    serviceName=$2

    echo -n "Stopping ${serviceName}…"
    "${commandName}" stop > /dev/null && echo " OK!"
}

#
# @param $1 Command name.
# @param $2 Service name.
#
function basho_service_restart() {
    commandName=$1
    serviceName=$2

    echo -n "Restarting ${serviceName}…"
    "${commandName}" restart > /dev/null && echo " OK!"
}


function riak_cs_create_buckets(){

    # Create buckets if the $RIAK_CS_BUCKETS variable is defined.

    if [ -v RIAK_CS_BUCKETS ]; then
        echo "Creating Riak CS buckets."
        riak_cs_admin_key_access=`cat /etc/stanchion/advanced.config | pcregrep -o 'admin_key, "\K(.{20})'`
        riak_cs_admin_key_secret=`cat /etc/stanchion/advanced.config | pcregrep -o 'admin_secret, "\K(.{40})'`

        IFS=$','; for bucket in $RIAK_CS_BUCKETS; do
            riak_cs_create_bucket "${riak_cs_admin_key_access}" "${riak_cs_admin_key_secret}" "${bucket}"
        done
        echo "Finished creating CS buckets"
    fi
}


# All services are stopped. Start them first.

basho_service_start 'riak' 'Riak'
basho_service_start 'stanchion' 'Stanchion'
basho_service_start 'riak-cs' 'Riak CS'

# Apparently sometimes services need extra time to warm up.

# Then create specified buckets.

riak_cs_create_buckets