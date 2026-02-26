#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail


# Postgres 14.12 (Dogu Version 14.15-2) fixed an issue with the visibility of hidden statistics
# since this fix comes after the version was released, always execute it if it was not executed before
# see https://www.postgresql.org/docs/14/release-14-12.html#:~:text=Restrict%20visibility%20of,WITH%20ALLOW_CONNECTIONS%20false%3B for more information
function runRestrictStatVisibility() {
  echo "Running restrictStatVisibility script..."

  local cveFixPath="/usr/share/postgresql/fix-CVE-2024-4317.sql"

  if [[ $(doguctl config --default "false" restricted_stat_visibility) == "true" ]] ; then
    echo "restricted_stat_visibility already set to true, skipping migration step..."
    return 0
  fi

  echo "Postgresql stats might be visible outside of their intended scope. Restricting stat visibility..."

  if [[ ! -f "${cveFixPath}" ]]; then
    echo "Did not find file ${cveFixPath}, skipping fix..."
    return 0
  fi

  local postgres_user
  postgres_user=$(doguctl config user)

  # temporarily accept connections on template0
  psql -U "${postgres_user}" -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS true;"

  # get all tables
  psql -U postgres -c "SELECT d.datname as \"Name\" FROM pg_catalog.pg_database d;" -X > databases
  # there are four lines of sql result information (two at the start, two at the end)
  for i in $(seq 3 $(($(wc -l < databases) - 2 ))); do
    DATABASE_NAME=$(sed "${i}!d" databases | xargs)
    psql -U "${postgres_user}" -d "${DATABASE_NAME}" -c "\i ${cveFixPath}"
  done
  # disable connections on template0
  psql -U "${postgres_user}" -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS false;"

  doguctl config restricted_stat_visibility true

  echo "Successfully run restrictStatVisibility script..."
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    runRestrictStatVisibility "$@"
fi