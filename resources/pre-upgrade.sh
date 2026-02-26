#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

BACKUP_DIR="/var/lib/postgresql/backup"

LOCKFILE="${BACKUP_DIR}/backup.lock"
BACKUP_FILE="${BACKUP_DIR}/full_backup_$(date +%F).sql"

# Cuts the dogu version from the version schema
# 14.18-3 -> 14.18
function get_base_version() {
  echo "$1" | cut -d'-' -f1
}

# returns the major version from the version schema
# 14.18-3 -> 14
function get_major_version() {
  echo "$1" | cut -d '.' -f1
}

function version_less_than() {
  [[ "$1" != "$2" && "$(printf '%s\n%s' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

function createFullBackup() {
  local postgres_user
  postgres_user=$(doguctl config user)

  # Prepare backup directory
  mkdir -p "$BACKUP_DIR"
  chown -R "${postgres_user}" "${BACKUP_DIR}"

  if [[ -f "$LOCKFILE" ]]; then
    echo "Lockfile $LOCKFILE already exists! Migration is running or has been canceled." >&2
    exit 1
  fi

  echo "Creating lock file ${LOCKFILE}..."
  touch "${LOCKFILE}"

  echo "Dumping database to ${BACKUP_FILE}..."
  if gosu "${postgres_user}" pg_dumpall -U "${postgres_user}" --clean --if-exists -f "${BACKUP_FILE}"; then
    doguctl config "migration_backup_path" "${BACKUP_FILE}"
    echo "Successfully created backup ${BACKUP_FILE}"
    rm "$LOCKFILE"
  else
    echo "An error occurred during backup!" >&2
    # Keep lock file to avoid consequential damage
    exit 1
  fi
}

function runPreUpgrade() {
  local FROM_VERSION="${1}"
  local TO_VERSION="${2}"

  if [[ -z "${FROM_VERSION}" || -z "${TO_VERSION}" ]]; then
    echo "Usage: $0 <FROM_VERSION> <TO_VERSION>" >&2
    exit 1
  fi

  local FROM_MAJOR_VERSION
  FROM_MAJOR_VERSION=$(get_major_version "${FROM_VERSION}")

  local TO_MAJOR_VERSION
  TO_MAJOR_VERSION=$(get_major_version "${TO_VERSION}")

  if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
    echo "FROM and TO versions are the same; Exiting..."
    exit 0
  fi

  # dump database if TO_MAJOR_VERSION is higher than FROM_MAJOR_VERSION
  if [[ "${TO_MAJOR_VERSION}" -gt "${FROM_MAJOR_VERSION}" ]]; then
    echo "create backup because of major upgrade from ${FROM_VERSION} to ${TO_VERSION}"
    createFullBackup

  elif version_less_than "$(get_base_version "${FROM_VERSION}")" "14.21"; then
    echo "create backup because volumes paths have been changed in version 14.21"
    createFullBackup
  fi

  echo "Set registry flag so startup script waits for post-upgrade to finish..."
  doguctl config "local_state" "upgrading"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runPreUpgrade "$@"
fi
