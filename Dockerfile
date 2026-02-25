ARG PG_MAJOR=14
ARG PG_MINOR=21

ARG ALPINE_VERSION=3.23

FROM registry.cloudogu.com/official/base:3.23.3-4 AS builder

FROM golang:1.26.0 AS gosu-builder

WORKDIR /gosu-src

# Clone the `gosu` source code and build it
RUN apt-get update && apt-get install -y git \
    && git clone https://github.com/tianon/gosu.git . \
    && git checkout 1.17 \
    && go build -o /usr/local/bin/gosu . \
    && chmod +x /usr/local/bin/gosu

FROM postgres:${PG_MAJOR}.${PG_MINOR}-alpine${ALPINE_VERSION}

ARG PG_MAJOR

LABEL NAME="official/postgresql" \
      VERSION="14.20-2" \
      maintainer="hello@cloudogu.com"

# === Copy doguctl ===
COPY --from=builder /usr/local/bin/doguctl /usr/local/bin/

# Copy the `gosu` binary built with the latest Go version
COPY --from=gosu-builder /usr/local/bin/gosu /usr/local/bin/gosu

# Copy migrations scripts
COPY resources/migrations/ /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh

COPY resources/ /
RUN rm -rf /migrations

# Starting from PostgreSQL version 18 PGDATA will be set to be version specific - we already opt-in to
# facilitate migration later - with version 18 this statement can be removed.
ENV PGDATA /var/lib/postgresql/${PG_MAJOR}/docker

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

ENTRYPOINT ["/startup.sh"]

CMD ["postgres"]
