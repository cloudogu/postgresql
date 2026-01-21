FROM registry.cloudogu.com/official/base:3.23.2-2 AS builder

# doguctl

FROM postgres:14.20-alpine3.23

LABEL NAME="official/postgresql" \
      VERSION="14.20-0" \
      maintainer="hello@cloudogu.com"

# === ENV: keep exactly the same contracts ===
ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql

# === Copy doguctl (same as before) ===
COPY --from=builder /usr/local/bin/doguctl /usr/local/bin/

COPY resources/ /

RUN set -eux; \
    mkdir -p "$PGDATA"; \
    chown -R postgres:postgres /var/lib/postgresql

VOLUME ["/var/lib/postgresql"]

HEALTHCHECK --interval=5s CMD doguctl healthy postgresql || exit 1

EXPOSE 5432

CMD ["/startup.sh"]
