#!/usr/bin/env bash

# Make sure we are in the same directory as the script and run relevant scripts in that order.

cd $(dirname $0)

. '/entrypoint/script/functions.sh'

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

function riak_cs_create_admin(){
    local riakCsConfigPath='/etc/riak-cs/advanced.config'
    local stanchionConfigPath='/etc/stanchion/advanced.config'

    if grep --quiet '%%{admin_key, null}' "${riakCsConfigPath}" && grep --quiet '%%{admin_secret, null}' "${riakCsConfigPath}"; then
        if [ -n "${RIAK_CS_KEY_ACCESS}" ] && [ -n "${RIAK_CS_KEY_SECRET}" ]; then
            local key_access="${RIAK_CS_KEY_ACCESS}"
            local key_secret="${RIAK_CS_KEY_SECRET}"
        else

            # Because we call this right after starting riak services, this sometimes fails with 500 status,
            # probably because it needs some time to warm up. This allows several attempts with delays.

            credentials=$(curl \
                --connect-timeout 5 \
                --fail \
                --header 'Content-Type: application/json' \
                --insecure \
                --request POST 'http://127.0.0.1:8080/riak-cs/user' \
                --retry 10 \
                --retry-delay 5 \
                --silent \
                --data '{"email":"admin@s3.amazonaws.com", "name":"admin"}')

            local key_access=$(echo -n $credentials | pcregrep -o '"key_id"\h*:\h*"\K([^"]*)')
            local key_secret=$(echo -n $credentials | pcregrep -o '"key_secret"\h*:\h*"\K([^"]*)')

            if [ -z "${key_access}" ] || [ -z "${key_secret}" ]; then
                echo "Could not create admin user and retrieve credentials. Curl got response:"
                echo "${credentials}"
                exit 1
            fi
        fi

        patchConfig "${riakCsConfigPath}" '\Q{anonymous_user_creation, true}\E' '{anonymous_user_creation, false}'
        patchConfig "${riakCsConfigPath}" '\Q%%{admin_key, null}\E' '{admin_key, "'"${key_access}"'"}'
        patchConfig "${riakCsConfigPath}" '\Q%%{admin_secret, null}\E' '{admin_secret, "'"${key_secret}"'"}'
        patchConfig "${stanchionConfigPath}" '\Q%%{admin_key, null}\E' '{admin_key, "'"${key_access}"'"}'
        patchConfig "${stanchionConfigPath}" '\Q%%{admin_secret, null}\E' '{admin_secret, "'"${key_secret}"'"}'

        # Create admin credentials.

        cat <<-EOL

			############################################################

			    Riak admin credentials, make note of them, otherwise you
			    will not be able to access your files and data. Riak
			    services will be restarted to take effect.

			    Access key: ${key_access}
			    Secret key: ${key_secret}

			############################################################

EOL

        basho_service_restart 'riak' 'Riak'
        basho_service_restart 'stanchion' 'Stanchion'
        basho_service_restart 'riak-cs' 'Riak CS'
    else
        local key_access=$(cat "${riakCsConfigPath}" | pcregrep -o '{admin_key,\h*"\K([^"]*)')
        local key_secret=$(cat "${riakCsConfigPath}" | pcregrep -o '{admin_secret,\h*"\K([^"]*)')

        cat <<-EOL

			############################################################

			    Admin user is already setup, you can view credentials
			    at the beginning of this log.

			############################################################

EOL
    fi

    # We still must export those two for creating buckets, which requires credentials for authentication.

    riak_cs_admin_key_access="${key_access}"
    riak_cs_admin_key_secret="${key_secret}"
}

function riak_cs_create_buckets(){

    # Create buckets if the $RIAK_CS_BUCKETS variable is defined.

    if [ -v RIAK_CS_BUCKETS ]; then
        echo "Creating Riak CS buckets."

        IFS=$','; for bucket in $RIAK_CS_BUCKETS; do
            riak_cs_create_bucket "${riak_cs_admin_key_access}" "${riak_cs_admin_key_secret}" "${bucket}"
        done
        echo "Finished creating CS buckets"
    fi
}

chown -R riak:riak /var/lib/riak
chmod 755 /var/lib/riak

# All services are stopped. Start them first.

basho_service_start 'riak' 'Riak'
basho_service_start 'stanchion' 'Stanchion'
basho_service_start 'riak-cs' 'Riak CS'

riak_cs_create_admin

basho_service_stop 'riak-cs' 'Riak CS'
basho_service_stop 'stanchion' 'Stanchion'
basho_service_stop 'riak' 'Riak'
