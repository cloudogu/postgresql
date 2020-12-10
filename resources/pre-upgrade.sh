#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

FROM_VERSION="${1}"
TO_VERSION="${2}"
FROM_MAJOR_VERSION=$(echo "${FROM_VERSION}" | cut -d '.' -f1)
TO_MAJOR_VERSION=$(echo "${TO_VERSION}" | cut -d '.' -f1)

# dump database if TO_MAJOR_VERSION is equal or higher than 12 and FROM_MAJOR_VERSION is lower than 12
if [[ "${TO_MAJOR_VERSION}" -gt 11 ]] && [[ "${FROM_MAJOR_VERSION}" -lt 12 ]]; then
    echo "Dumping database to ${PGDATA}/postgresqlFullBackup.dump..."
    pg_dumpall -U postgres -f "${PGDATA}"/postgresqlFullBackup.dump
    echo "Finished dumping database"
fi
