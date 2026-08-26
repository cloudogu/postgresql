#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/util.sh"
source "/usr/local/bin/docker-entrypoint.sh"

: "${PGDATA:?PGDATA is not set. Abort post-upgrade as the script needs the environment variable.}"

function rotateSuperuserPassword(){
  echo "rotate superuser password once"
  
  # receive flag indicating if password was rotated
  local alreadyRotated;
  alreadyRotated=$(doguctl config --default "false" "password_rotated")
  
  # if already rotated, leave
  if [[ ${alreadyRotated} ]]; then
    echo "superuser password already rotated"
    exit 0
  fi

  # generate new password
  local newSuperuserPassword;
  newSuperuserPassword=$(doguctl random )
  
  # 1. store the user in local config
  doguctl config -e password "${newSuperuserPassword}"

  # get the postgres user
  local postgresUser;
  postgresUser=$(doguctl config user "${POSTGRES_USER}")

  # 2. change the user in the database
  psql -U "${ADMIN_USERNAME}" -c "ALTER USER ${postgresUser} WITH PASSWORD ${newSuperuserPassword}"

  # rotation completed
  doguctl config "password_rotated" "true"

}

function startPostgresql() {
  echo "starting postgresql temporary"
  docker_temp_server_start postgres
  rotateSuperuserPassword
}

function stopPostgresql() {
  echo "stopping temporary postgresql"
  docker_temp_server_stop
}

function runMigrations() {
  #run migrations manually
  for script in /docker-entrypoint-initdb.d/*.sh; do
    echo "Manually executing $script..."
    "$script"
  done
}

# New PostgreSQL version requires completely empty folder
function prepareForRestore() {
  echo "Preparing storage for restore..."

  # Handle databases from old version where data is stored within /var/lib/postgresql
  if [[ -s "/var/lib/postgresql/PG_VERSION" ]]; then
    echo "Found legacy database in volume root, cleaning up..."

    # Protected folders:
    # - backup: holds the backup to be restored
    # - data: is the volume mount of the postgres image 14
    # - 14, 15, ect. : Database folder for the upgrade
    cd /var/lib/postgresql/
    find . -maxdepth 1 ! -name '.' ! -name 'backup' ! -name 'data' ! -name "${PG_MAJOR%%.*}" -exec rm -rf {} +
  fi

  if [[ -d "${PGDATA}" ]]; then
    echo "Cleaning target directory ${PGDATA}..."
    find "${PGDATA}" -mindepth 1 -delete
  fi

  mkdir -p "${PGDATA}"
}

function runPostUpgrade() {
    FROM_VERSION="${1}"
    TO_VERSION="${2}"

    echo "Running post upgrade from version ${FROM_VERSION} to ${TO_VERSION}"

    if [[ "${FROM_VERSION}" = "${TO_VERSION}" ]]; then
      echo "FROM and TO versions are the same; Exiting..."
      doguctl config --rm "local_state"
      exit 0
    fi

    local user; user=$(doguctl config -d "postgres" user)
    export PGUSER="${user}"

    #fix permissions in volume root
    chown -R "${user}" /var/lib/postgresql/

    if [[ $(doguctl config -d "empty" "migration_backup_path") != "empty" ]] ; then
      echo "backup found in config, prepare for restore..."
      prepareForRestore

      doguctl config --rm "local_state"
      exit 0
    fi

    if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
      echo "PostgreSQL does not seem to be initialized, skip post upgrade..."
      doguctl config --rm "local_state"
      exit 0
    fi

    #switch to postgres user
    if [ "$(id -u)" = '0' ]; then
      exec gosu postgres "$BASH_SOURCE" "$@"
    fi

    startPostgresql
    runMigrations
    stopPostgresql

    doguctl config --rm "local_state"
    echo "Postgresql post-upgrade done"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    runPostUpgrade "$@"
fi
