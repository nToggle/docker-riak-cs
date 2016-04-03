# Docker Riak CS

<div align="center"><img src="./documentation/asset/docker-riak-cs-s3.png"></div>

[Riak CS](http://docs.basho.com/riakcs/latest/) is an object storage software [compatible](http://docs.basho.com/riakcs/latest/references/apis/storage/s3/) with [AWS S3](http://aws.amazon.com/s3/) API. It's a perfect S3 alternative for local development and testing, which is the exact purpose of this image. It works as a single node to keep the resources to the minimum, something that [Riak guys wouldn't recommend](http://basho.com/why-your-riak-cluster-should-have-at-least-five-nodes/) and certainly not suitable for production. There is [hectcastro/docker-riak-cs](https://github.com/hectcastro/docker-riak-cs) project that allows to bring up a multi-node cluster, which might suite you better.

## Running

Pull or build the image yourself and run it. When the container gets started it will setup the Riak admin and show you the credentials. Will also create optionally provided buckets.

```sh
# Build
docker build --tag "quay.io/ntoggle/riak-cs:$IMAGE_VERSION" "./src"

 
# Run and create three buckets
docker run -dP -e 'RIAK_CS_BUCKETS=foo,bar,baz' -p '8080:8080' --name 'riak-cs' quay.io/ntoggle/riak-cs:$IMAGE_VERSION

# Usage for s3cmd

cat <<EOF >~/.s3cfg.riak_cs
[default]
access_key = <RIAK_CS_KEY_ACCESS>
host_base = s3.amazonaws.com
host_bucket = %(bucket)s.s3.amazonaws.com
proxy_host = 127.0.0.1
proxy_port = 8080
secret_key = <RIAK_CS_KEY_SECRET>
signature_v2 = True
use_https = False
EOF

s3cmd -c ~/.s3cfg.riak_cs ls  # Retry a couple of seconds later if you get ERROR: [Errno 104] Connection reset by peer
```

## Configuration

You can use the following environment variables to configure Riak CS instance:

- `RIAK_CS_BUCKETS` – colon separated list or buckets to automatically create.

## Scripts

All image and container business is done in individual scripts instead of using docker file for all of that. During the build we run `build.sh` which runs scripts that install dependencies and patch configuration, while `entrypoint.sh` only configures the application when the container starts.

<div align="center"><img src="./documentation/asset/scripts.png"></div>

## Container ops

```sh
# Connect to an existing container.
docker exec -it 'riak-cs' bash


# Remove exited containers.
docker ps -a | grep 'Exited' | awk '{print $1}' | xargs docker rm

# Remove intermediary and unused images.
docker rmi $(docker images -aq -f 'dangling=true')
```
