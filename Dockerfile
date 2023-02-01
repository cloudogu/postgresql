FROM registry.cloudogu.com/official/base:3.17.1-1

LABEL NAME="official/postgresql" \
        VERSION="12.10-1" \
        maintainer="hello@cloudogu.com"

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql \
    POSTGRESQL_VERSION=12.13-r1 \
    GOSU_SHA256=0f25a21cf64e58078057adc78f38705163c1d564a959ff30a891c31917011a54

# install postgresql and gosu
# Note: the current postgresql version from alpine is installed
# https://pkgs.alpinelinux.org/packages?name=postgresql&branch=v3.12&arch=x86_64
RUN set -x -o errexit \
 && set -o nounset \
 && set -o pipefail \
 && apk update \
 && apk upgrade \
 && apk add --update postgresql12="${POSTGRESQL_VERSION}" \
 && wget --progress=bar:force:noscroll "https://github.com/tianon/gosu/releases/download/1.12/gosu-amd64" \
 && echo "${GOSU_SHA256} *gosu-amd64" | sha256sum -c - \
 && mv /gosu-amd64 /usr/local/bin/gosu \
 && chmod +x /usr/local/bin/gosu \
 && rm -rf /var/cache/apk/*

COPY resources/ /

VOLUME ["/var/lib/postgresql"]

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

CMD ["/startup.sh"]
