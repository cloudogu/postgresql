FROM registry.cloudogu.com/official/base:3.6-2

LABEL NAME="official/postgresql" \
        VERSION="9.6.13-1" \
        maintainer="christian.beyer@cloudogu.com"

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql \
    POSTGRESQL_VERSION=9.6.13-r0 \
    GOSU_SHA256=5b3b03713a888cee84ecbf4582b21ac9fd46c3d935ff2d7ea25dd5055d302d3c


# install postgresql and gosu
# Note: the current postgresql version from alpine is installed
# https://pkgs.alpinelinux.org/packages?name=postgresql&branch=v3.6&repo=&arch=x86_64
RUN apk update \
 && apk add --update postgresql="${POSTGRESQL_VERSION}" \
 && wget --progress=bar:force:noscroll "https://github.com/tianon/gosu/releases/download/1.10/gosu-amd64" \
 && echo "${GOSU_SHA256} *gosu-amd64" | sha256sum -c - \
 && mv /gosu-amd64 /usr/local/bin/gosu \
 && chmod +x /usr/local/bin/gosu \
 && rm -rf /var/cache/apk/*

COPY resources/ /

VOLUME ["/var/lib/postgresql"]

HEALTHCHECK CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

CMD ["/startup.sh"]
