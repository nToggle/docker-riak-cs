FROM debian:7.9
MAINTAINER Johnny Everson <j.everson@ntoggle.com>

ENV DEBIAN_FRONTEND noninteractive

ADD ./script/install_dependencies.sh /

RUN . /install_dependencies.sh

COPY . /docker
RUN /docker/script/build.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["riak"]
