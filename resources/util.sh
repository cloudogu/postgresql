#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


function initializePostgreSQL() {
    # set stage for health check
    doguctl state installing

    # install database
    gosu postgres initdb

    # postgres user
    POSTGRES_USER="postgres"

    # store the user
    doguctl config user "${POSTGRES_USER}"

    # create random password
    POSTGRES_PASSWORD=$(doguctl random)

    # store the password encrypted
    doguctl config -e password "${POSTGRES_PASSWORD}"

    # open port
    sed -ri "s/^#(listen_addresses\s*=\s*)\S+/\1'*'/" "$PGDATA"/postgresql.conf

    # set generated password
    echo "ALTER USER ${POSTGRES_USER} WITH SUPERUSER PASSWORD '${POSTGRES_PASSWORD}';" | gosu 2>/dev/null 1>&2 postgres postgres --single -jE
}

function chownPgdata() {
    chown -R postgres "$PGDATA"

    # create /run/postgresql, if not existent
    mkdir -p /run/postgresql
    chown postgres:postgres /run/postgresql
}