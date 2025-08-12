#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function runPreUpgrade() {
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

  if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
    echo "FROM and TO versions are the same; Exiting..."
    exit 0
  fi

  echo "Set registry flag so startup script waits for post-upgrade to finish..."
  doguctl config "local_state" "upgrading"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runPreUpgrade "$@"
fi
