#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

FROM_VERSION="${1}"
TO_VERSION="${2}"
FROM_MAJOR_VERSION=$(echo "${FROM_VERSION}" | cut -d '.' -f1)
TO_MAJOR_VERSION=$(echo "${TO_VERSION}" | cut -d '.' -f1)

# dump database if TO_MAJOR_VERSION is higher than FROM_MAJOR_VERSION
if [[ "${TO_MAJOR_VERSION}" -gt "${FROM_MAJOR_VERSION}" ]]; then
    echo "Dumping database to ${PGDATA}/postgresqlFullBackup.dump..."
    pg_dumpall -U postgres -f "${PGDATA}"/postgresqlFullBackup.dump
    echo "Finished dumping database"
fi
