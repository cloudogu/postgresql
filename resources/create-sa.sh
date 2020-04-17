#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

{
    SERVICE="$1"
    if [ X"${SERVICE}" = X"" ]; then
        echo "usage create-sa.sh servicename"
        exit 1
    fi

    COLLATION="$2"
    if [[ ! $COLLATION == *".UTF-8"* ]]; then
      echo "encodings other than 'UTF-8' are not allowed"
      exit 1
    fi
    LC=${COLLATION%%".UTF-8"}

    # create random schema suffix and password
    ID=$(doguctl random -l 6 | tr '[:upper:]' '[:lower:]')
    USER="${SERVICE}_${ID}"
    PASSWORD=$(doguctl random)
    DATABASE="${USER}"

    # connection user
    ADMIN_USERNAME=$(doguctl config user)

    # create role
    psql -U "${ADMIN_USERNAME}" -c "CREATE USER ${USER} WITH PASSWORD '${PASSWORD}';"
    CREATE_DB_COMMAND="CREATE DATABASE ${DATABASE} OWNER ${USER} ENCODING 'UTF-8'"
    if [[ $LC ]]; then
      # the passed collation differs from the default collation so another template has to be used
      # see: https://www.postgresql.org/docs/9.0/sql-createdatabase.html#AEN60123
      CREATE_DB_COMMAND="${CREATE_DB_COMMAND} LC_COLLATE '${LC}' LC_CTYPE '${LC}' TEMPLATE template0"
    fi
    # create database
    psql -U "${ADMIN_USERNAME}" -c "${CREATE_DB_COMMAND};"

} >/dev/null 2>&1

# print details
echo "database: ${DATABASE}"
echo "username: ${USER}"
echo "password: ${PASSWORD}"
