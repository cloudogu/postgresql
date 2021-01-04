FROM golang:1.14-alpine3.12 AS builder

ENV WORKDIR=/go/src/postgresql/startup

RUN mkdir -p ${WORKDIR}
WORKDIR ${WORKDIR}

COPY ./startup ${WORKDIR}

RUN go build



FROM registry.cloudogu.com/official/base:3.12.1-1

LABEL NAME="official/postgresql" \
        VERSION="12.5-2" \
        maintainer="christian.beyer@cloudogu.com"

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql \
    POSTGRESQL_VERSION=12.5-r0 \
    GOSU_SHA256=0f25a21cf64e58078057adc78f38705163c1d564a959ff30a891c31917011a54

# install postgresql and gosu
# Note: the current postgresql version from alpine is installed
# https://pkgs.alpinelinux.org/packages?name=postgresql&branch=v3.12&arch=x86_64
RUN apk update \
 && apk add --update postgresql="${POSTGRESQL_VERSION}" \
 && wget --progress=bar:force:noscroll "https://github.com/tianon/gosu/releases/download/1.12/gosu-amd64" \
 && echo "${GOSU_SHA256} *gosu-amd64" | sha256sum -c - \
 && mv /gosu-amd64 /usr/local/bin/gosu \
 && chmod +x /usr/local/bin/gosu \
 && rm -rf /var/cache/apk/*

COPY resources/ /

COPY --from=builder /go/src/postgresql/startup/startup /

VOLUME ["/var/lib/postgresql"]

HEALTHCHECK CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

CMD ["/startup"]
