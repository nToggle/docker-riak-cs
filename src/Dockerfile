FROM debian:7.9
MAINTAINER Johnny Everson <j.everson@ntoggle.com>

ENV DEBIAN_FRONTEND noninteractive

COPY . /docker
RUN /docker/script/build.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["riak"]
