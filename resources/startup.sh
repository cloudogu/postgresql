#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

echo "                                     ./////,                    "
echo "                                 ./////==//////*                "
echo "                                ////.  ___   ////.              "
echo "                         ,**,. ////  ,////A,  */// ,**,.        "
echo "                    ,/////////////*  */////*  *////////////A    "
echo "                   ////'        \VA.   '|'   .///'       '///*  "
echo "                  *///  .*///*,         |         .*//*,   ///* "
echo "                  (///  (//////)**--_./////_----*//////)   ///) "
echo "                   V///   '°°°°      (/////)      °°°°'   ////  "
echo "                    V/////(////////\. '°°°' ./////////(///(/'   "
echo "                       'V/(/////////////////////////////V'      "
echo "                                                                "
echo "                               Powered by Cloudogu              "
echo "                                                                "
echo "                                                                "

CUSTOM_HBA="/pg_hba.conf"

function initAdmin() {
  # postgres is the default user running the database
  POSTGRES_USER="postgres"

  # store the user in local config
  doguctl config user "${POSTGRES_USER}"

  # create an initial random password
  local postgres_psw
  postgres_psw=$(doguctl random)

  # store the password encrypted
  doguctl config -e password "${postgres_psw}"

  # store the marker to indicate the password was encrypted new and safe
  doguctl config "password_rotated" "true"
}

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

# See https://www.postgresql.org/docs/14/runtime-config-logging.html
function mapDoguLogLevel() {
  local currentLogLevel
  currentLogLevel=$(doguctl config --default "WARN" "logging/root")

  case "${currentLogLevel}" in
    "ERROR") echo "ERROR"   ;;
    "INFO")  echo "INFO"    ;;
    "DEBUG") echo "DEBUG5"  ;;
    *)       echo "WARNING" ;;
  esac
}

function getMaxConnections() {
  doguctl config 'database_config/max_connections'
}

function runMain() {
  # check whether post-upgrade script is still running
  while [[ "$(doguctl config "local_state" -d "empty")" == "upgrading" ]]; do
    echo "Post-Upgrade script is running. Waiting..."
    sleep 3
  done

  # fresh install
  if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "Install new postgresql instance..."
    doguctl state installing
    initAdmin
  fi

# PSEUDO
  # check value of "password_rotated" from dogu config via "doguctl config" 
  # if [["$(doguctl config "rotated" == ""]] # empty, non existent
  # then call new function "rotate_default_user_password"
  # 

  echo "Writing custom hba file in ${CUSTOM_HBA}..."
  create_hba > "${CUSTOM_HBA}"

  echo "Mapping dogu specific log level..."
  POSTGRESQL_LOGLEVEL=$(mapDoguLogLevel)

  echo "Get max connections for postgresql..."
  POSTGRES_MAX_CONNECTIONS=$(getMaxConnections)

  echo "Setting superuser password for postgresql"
  POSTGRES_PASSWORD=$(doguctl config -e password)
  export POSTGRES_PASSWORD

  # make sure /var/ces/state can be used by the postgres user
  if [ -d "/var/ces/state" ]; then
    chown -R postgres:postgres "/var/ces/state"
  fi

  doguctl state ready

  exec /usr/local/bin/docker-entrypoint.sh "$@" \
    -c hba_file="${CUSTOM_HBA}" \
    -c listen_addresses="*" \
    -c log_min_messages="${POSTGRESQL_LOGLEVEL}" \
    -c max_connections="${POSTGRES_MAX_CONNECTIONS}"
}

# make the script only run when executed, not when sourced from bats tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  runMain "$@"
fi