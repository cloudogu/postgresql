#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"

function prepareForBackup() {
    isBackupAvailable=true
    # Moving backup and emptying PGDATA directory
    mv "${PGDATA}"/postgresqlFullBackup.dump /tmp/postgresqlFullBackup.dump

    # New PostgreSQL version requires completely empty folder
    rm -rf "${PGDATA:?}"/.??*
    rm -rf "${PGDATA:?}"/*

    initializePostgreSQL
}

function startPostgresql() {
    echo "start postgresql"
    gosu postgres postgres &
    PID=$!

    while ! pg_isready >/dev/null; do
      # Postgres is not ready yet to accept connections
      sleep 0.1
    done
}

function restoreBackup() {
    echo "Restoring database dump..."
    psql -U postgres -f /tmp/postgresqlFullBackup.dump postgres
    rm /tmp/postgresqlFullBackup.dump
    echo "Restoring database dump...complete!"
}

# see https://www.postgresql.org/docs/14/release-14-12.html#:~:text=Restrict%20visibility%20of,WITH%20ALLOW_CONNECTIONS%20false%3B for more information
function restrictStatVisibility() {
    if [ ! -f /usr/share/postgresql/fix-CVE-2024-4317.sql ]; then
        return 0
    fi

    while ! pg_isready >/dev/null; do
        # Postgres is not ready yet to accept connections
        sleep 0.1
    done
    # temporarily accept connections on template0
    psql -U postgres -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS true;"

    # get all tables
    psql -U postgres -c "SELECT d.datname as \"Name\" FROM pg_catalog.pg_database d;" -X > databases
    # there are four lines of sql result information (two at the start, two at the end)
    for i in $(seq 3 $(($(wc -l < databases) - 2 ))); do
        DATABASE_NAME=$(sed "${i}!d" databases | xargs)
        psql -U postgres -d "${DATABASE_NAME}" -c "\i /usr/share/postgresql/fix-CVE-2024-4317.sql"
    done
    # disable connections on template0
    psql -U postgres -c "ALTER DATABASE template0 WITH ALLOW_CONNECTIONS false;"
    doguctl config restricted_stat_visibility true
}

function reindexAllDatabases() {
    while ! pg_isready >/dev/null; do
        # Postgres is not ready yet to accept connections
        sleep 0.1
    done
    reindexdb -U postgres --verbose --all
}

# versionXLessOrEqualThanY returns true if X is less than or equal to Y; otherwise false
function versionXLessOrEqualThanY() {
  local sourceVersion="${1}"
  local targetVersion="${2}"

  if [[ "${sourceVersion}" == "${targetVersion}" ]]; then
    echo "upgrade to same version"
    return 0
  fi

  declare -r semVerRegex='([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)'

   sourceMajor=0
   sourceMinor=0
   sourceBugfix=0
   sourceDogu=0
   targetMajor=0
   targetMinor=0
   targetBugfix=0
   targetDogu=0

  if [[ ${sourceVersion} =~ ${semVerRegex} ]]; then
    sourceMajor=${BASH_REMATCH[1]}
    sourceMinor="${BASH_REMATCH[2]}"
    sourceBugfix="${BASH_REMATCH[3]}"
    sourceDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: source dogu version ${sourceVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ ${targetVersion} =~ ${semVerRegex} ]]; then
    targetMajor=${BASH_REMATCH[1]}
    targetMinor="${BASH_REMATCH[2]}"
    targetBugfix="${BASH_REMATCH[3]}"
    targetDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: target dogu version ${targetVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ $((sourceMajor)) -lt $((targetMajor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -lt $((targetMinor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -lt $((targetBugfix)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -le $((targetBugfix)) && $((sourceDogu)) -lt $((targetDogu)) ]] ; then
    return 0;
  fi

  return 1
}

function migrateConstraintsOnPartitionedTables() {
    while ! pg_isready >/dev/null; do
      # Postgres is not ready yet to accept connections
      sleep 0.1
    done
    # get all tables
    psql -U postgres -c "SELECT d.datname as \"Name\" FROM pg_catalog.pg_database d;" -X > databases
    # there are four lines of sql result information (two at the start, two at the end)
    for i in $(seq 3 $(($(wc -l < databases) - 2 )));
    do
        DATABASE_NAME=$(sed "${i}!d" databases | xargs)
        # skip postgres default tables
        if [ "${DATABASE_NAME}" != "template0" ] && [ "${DATABASE_NAME}" != "template1" ] && [ "${DATABASE_NAME}" != "postgres" ]; then
            # https://www.postgresql.org/docs/14/release-14-14.html#:~:text=Fix%20updates%20of,perform%20each%20step.
            QUERY="SELECT conrelid::pg_catalog.regclass AS \"constrained table\",
                                              conname AS constraint,
                                              confrelid::pg_catalog.regclass AS \"references\",
                                              pg_catalog.format('ALTER TABLE %s DROP CONSTRAINT %I;',
                                                                conrelid::pg_catalog.regclass, conname) AS \"drop\",
                                              pg_catalog.format('ALTER TABLE %s ADD CONSTRAINT %I %s;',
                                                                conrelid::pg_catalog.regclass, conname,
                                                                pg_catalog.pg_get_constraintdef(oid)) AS \"add\"
                                       FROM pg_catalog.pg_constraint c
                                       WHERE contype = 'f' AND conparentid = 0 AND
                                          (SELECT count(*) FROM pg_catalog.pg_constraint c2
                                           WHERE c2.conparentid = c.oid) <>
                                          (SELECT count(*) FROM pg_catalog.pg_inherits i
                                           WHERE (i.inhparent = c.conrelid OR i.inhparent = c.confrelid) AND
                                             EXISTS (SELECT 1 FROM pg_catalog.pg_partitioned_table
                                                     WHERE partrelid = i.inhparent));"
            psql -U postgres -c "${QUERY}"  -d "${DATABASE_NAME}" > result_queries
            # Do not run migration if result is empty
            if ! grep -q "0 rows" result_queries; then
                    echo "Found constraints on partitioned tables in database ${DATABASE_NAME} while performing the upgrade."
                    echo "Migrating ${DATABASE_NAME} now"
                    AMOUNT=$(wc -l < result_queries)
                    for (( i = 3; i < ((AMOUNT - 1)); i++ )); do
                        IFS='|' read -ra ADDR <<< "$(sed "$((i))q;d" result_queries)"
                        echo "Migrating entry $((i - 2))/$(((AMOUNT - 4))) in table${ADDR[1]}"
                        # drop constraint query
                        psql -U postgres -c "${ADDR[3]}" -d "${DATABASE_NAME}" >> /dev/null
                        # readd constraint querysql_queries_test
                        psql -U postgres -c "${ADDR[4]}" -d "${DATABASE_NAME}" >> /dev/null
                    done
            fi
        fi
    done
    # set config key so migration is only done once
    doguctl config migrated_database_constraints true
}

function killPostgresql() {
    # Kill postgres
    pkill -P ${PID}
    kill ${PID}

    while pgrep -x postgres >/dev/null; do
      # Postgres is still running
      sleep 0.1
    done
    echo "postgresql successfully killed (this is expected during post upgrade)"
}

function runPostUpgrade() {
    FROM_VERSION="${1}"
    TO_VERSION="${2}"

    isBackupAvailable=false
    if [ -e "${PGDATA}"/postgresqlFullBackup.dump ]; then
        prepareForBackup
    fi

    startPostgresql

    if [ "${isBackupAvailable}" = "true" ]; then
        restoreBackup
    fi

    if [[ $(doguctl config --default "false" restricted_stat_visibility) != "true" ]] ; then
        # Postgres 14.12 (Dogu Version 14.15-2) fixed an issue with the visibility of hidden statistics
        # since this fix comes after the version was released, always execute it if it was not executed before
        echo "Postgresql stats might be visible outside of their intended scope. Restricting stat visibility..."
        restrictStatVisibility
    fi
    if [ "${FROM_VERSION}" = "${TO_VERSION}" ]; then
        echo "FROM and TO versions are the same; Exiting..."
        doguctl config --rm "local_state"
        exit 0
    else
        echo "Postgresql version changed. Reindexing all databases..."
        reindexAllDatabases
    fi

    if versionXLessOrEqualThanY "0.14.15-1" "0.${TO_VERSION}" && [[ $(doguctl config --default "false" migrated_database_constraints) != "true" ]] ; then
        # Postgres 14.14 (Dogu Version 14.15.x) fixed an issue with constraints on partitioned tables
        # If any partitioned tables have constraints on them, this migration removes and readds them
        migrateConstraintsOnPartitionedTables
    fi

    killPostgresql

    echo "Removing local_state registry flag so startup script can start afterwards..."
    doguctl config --rm "local_state"

    echo "Postgresql post-upgrade done"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    runPostUpgrade "$@"
fi
