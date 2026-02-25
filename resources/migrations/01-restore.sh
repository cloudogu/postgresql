#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function runRestore() {
  echo "Running restore script..."

  local backupFile
  backupFile=$(doguctl config -d "empty" "migration_backup_path")

  if [[ "${backupFile}" == "empty" ]]; then
    echo "No backup found in config, skipping restore..."
    return 0
  fi

  if [[ ! -f "${backupFile}" ]]; then
    echo "ERROR: Backup file ${backupFile} not found on disk!" >&2
    exit 1
  fi

  doguctl state "upgrading"

  local postgres_user
  postgres_user=$(doguctl config user)

  echo "Performing PostgreSQL Restore..."

  # We filter the dump before passing it to psql.
  # This prevents the ‘postgres’ user from deleting or modifying itself.
  # - ON_ERROR_STOP=1 remains active to abort in case of real data errors.
  sed -e '/DROP ROLE IF EXISTS '"${postgres_user}"';/d' \
      -e '/CREATE ROLE '"${postgres_user}"';/d' \
      -e '/ALTER ROLE '"${postgres_user}"'/d' \
      "${backupFile}" | psql -v ON_ERROR_STOP=1 -U "${postgres_user}"

  echo "Restoring data finished successfully."

  echo "Cleaning backup file..."
  rm -f "${backupFile}"

  echo "Cleaning up backup flag in config..."
  doguctl config --rm "migration_backup_path"

  doguctl state "ready"

  echo "Successfully run restore script..."
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    runRestore "$@"
fi