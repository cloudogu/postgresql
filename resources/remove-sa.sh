#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

SERVICE="${1}"
if [ X"${SERVICE}" = X"" ]; then
    echo "usage remove-sa.sh servicename"
    exit 1
fi

# connection user
ADMIN_USERNAME=$(doguctl config user)

SELECT_DB_NAMES="SELECT datname FROM pg_database WHERE datistemplate=false AND datname like '${SERVICE}\_______'"

for database_name in $(psql -U "${ADMIN_USERNAME}" -t -c "${SELECT_DB_NAMES}")
do
  echo "Deleting service account '${database_name}'"
  psql -U "${ADMIN_USERNAME}" -c "DROP DATABASE if exists ${database_name};" >/dev/null 2>&1
  psql -U "${ADMIN_USERNAME}" -c "DROP USER if exists ${database_name};" >/dev/null 2>&1
done
