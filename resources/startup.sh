#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# shellcheck disable=SC1091
source util.sh

function mask2cidr() {
  local storedIFS="${IFS}"
  NBITS=0
  IFS=.
  for DEC in $1; do
    case $DEC in
    255) ((NBITS += 8)) ;;
    254)
      ((NBITS += 7))
      break
      ;;
    252)
      ((NBITS += 6))
      break
      ;;
    248)
      ((NBITS += 5))
      break
      ;;
    240)
      ((NBITS += 4))
      break
      ;;
    224)
      ((NBITS += 3))
      break
      ;;
    192)
      ((NBITS += 2))
      break
      ;;
    128)
      ((NBITS += 1))
      break
      ;;
    0) ;;
    *)
      echo "Error: ${DEC} is not recognised"
      exit 1
      ;;
    esac
  done
  IFS="${storedIFS}"
  echo "${NBITS}"
}

function create_hba() {
  echo '# generated, do not override'
  echo '# "local" is for Unix domain socket connections only'
  echo 'local   all             all                                     trust'
  echo '# IPv4 local connections:'
  echo 'host    all             all             127.0.0.1/32            trust'
  echo '# IPv6 local connections:'
  echo 'host    all             all             ::1/128                 trust'
  echo '# container networks'
  if [[ "$(doguctl multinode)" = "false" ]]; then
    for NETWITHMASK in $(netstat -nr | tail -n +3 | grep -v '^0' | awk '{print $1"/"$3}'); do
      local NET
      NET=$(echo "${NETWITHMASK}" | awk -F'/' '{print $1}')
      local MASK
      MASK=$(echo "${NETWITHMASK}" | awk -F'/' '{print $2}')
      local CIDR
      CIDR=$(mask2cidr "$MASK")
      echo "host    all             all             ${NET}/${CIDR}          password"
    done
  else
    echo "host    all             all             all          password"
  fi
}

function write_pg_hba_conf() {
  create_hba >"${PGDATA}"/pg_hba.conf
}

function waitForPostgreSQLStartup() {
  while ! pg_isready >/dev/null; do
    # Postgres is not ready yet to accept connections
    sleep 0.1
  done
}

function waitForPostgreSQLShutdown() {
  while pgrep -x postgres >/dev/null; do
    # Postgres is still running
    sleep 0.1
  done
}

# See https://www.postgresql.org/docs/14/runtime-config-logging.html
function setDoguLogLevel() {
  echo "Mapping dogu specific log level..."
  currentLogLevel=$(doguctl config --default "WARN" "logging/root")

  case "${currentLogLevel}" in
  "ERROR")
    export POSTGRESQL_LOGLEVEL="ERROR"
    ;;
  "INFO")
    export POSTGRESQL_LOGLEVEL="INFO"
    ;;
  "DEBUG")
    export POSTGRESQL_LOGLEVEL="DEBUG5"
    ;;
  *)
    export POSTGRESQL_LOGLEVEL="WARNING"
    ;;
  esac
  # Remove old log level setting, if existent
  sed -i '/^log_min_messages/d' /var/lib/postgresql/postgresql.conf
  # Append new log level setting
  echo "log_min_messages = ${POSTGRESQL_LOGLEVEL}" >>/var/lib/postgresql/postgresql.conf
}

function runMain() {
  chown -R postgres "$PGDATA"

  # create /run/postgresql, if not existent
  mkdir -p /run/postgresql
  chown postgres:postgres /run/postgresql

  # check whether post-upgrade script is still running
  while [[ "$(doguctl config "local_state" -d "empty")" == "upgrading" ]]; do
    echo "Upgrade script is running. Waiting..."
    sleep 3
  done

  if [ -z "$(ls -A "$PGDATA")" ]; then
    initializePostgreSQL
  fi

  write_pg_hba_conf
  setDoguLogLevel

  # set stage for health check
  doguctl state ready

  # start database
  exec gosu postgres postgres
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runMain
fi
