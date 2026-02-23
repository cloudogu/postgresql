FROM registry.cloudogu.com/official/base:3.23.3-3 AS builder

FROM golang:1.26.0 AS gosu-builder

WORKDIR /gosu-src

# Clone the `gosu` source code and build it
RUN apt-get update && apt-get install -y git \
    && git clone https://github.com/tianon/gosu.git . \
    && git checkout 1.17 \
    && go build -o /usr/local/bin/gosu . \
    && chmod +x /usr/local/bin/gosu

# get doguctl

FROM postgres:14.21-alpine3.23

LABEL NAME="official/postgresql" \
      VERSION="14.20-2" \
      maintainer="hello@cloudogu.com"

# === Copy doguctl ===
COPY --from=builder /usr/local/bin/doguctl /usr/local/bin/

# Copy the `gosu` binary built with the latest Go version
COPY --from=gosu-builder /usr/local/bin/gosu /usr/local/bin/gosu

COPY resources/ /

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

ENTRYPOINT ["/startup.sh"]

CMD ["postgres"]
