FROM registry.cloudogu.com/official/base:3.20.2-1 as builder

ENV GOSU_SHA256=bbc4136d03ab138b1ad66fa4fc051bafc6cc7ffae632b069a53657279a450de3

WORKDIR /build

RUN set -x -o errexit \
 && set -o nounset \
 && set -o pipefail \
 && apk update \
 && apk upgrade \
 && apk add wget \
 && mkdir -p /build/usr/local/bin \
 && wget --progress=bar:force:noscroll -O /build/usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64" \
 && echo "${GOSU_SHA256} */build/usr/local/bin/gosu" | sha256sum -c - \
 && chmod +x /build/usr/local/bin/gosu

FROM registry.cloudogu.com/official/base:3.20.2-1

LABEL NAME="official/postgresql" \
        VERSION="14.12-2" \
        maintainer="hello@cloudogu.com"

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql \
    POSTGRESQL_VERSION=14.12-r0

# install postgresql and gosu
# Note: the current postgresql version from alpine is installed
# https://pkgs.alpinelinux.org/packages?name=postgresql&branch=v3.12&arch=x86_64
RUN set -x -o errexit \
 && set -o nounset \
 && set -o pipefail \
 && apk update \
 && apk upgrade \
 && apk add --no-cache --update postgresql14="${POSTGRESQL_VERSION}"

COPY resources/ /
COPY --from=builder /build /

VOLUME ["/var/lib/postgresql"]

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

CMD ["/startup.sh"]
