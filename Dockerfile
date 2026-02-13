FROM registry.cloudogu.com/official/base:3.23.3-3 AS builder

# get doguctl

FROM postgres:14.20-alpine3.23

LABEL NAME="official/postgresql" \
      VERSION="14.20-1" \
      maintainer="hello@cloudogu.com"

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql/data

# === Copy doguctl ===
COPY --from=builder /usr/local/bin/doguctl /usr/local/bin/

COPY resources/ /

RUN set -eux; \
    mkdir -p "${PGDATA}"; \
    chown -R postgres:postgres "${PGDATA}"

VOLUME ["/var/lib/postgresql/data"]

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

ENTRYPOINT []

CMD ["/startup.sh"]
