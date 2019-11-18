#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

# TODO: Only dump database if necessary
# e.g. at major upgrades, not at bugfix upgrades
pg_dumpall -U postgres -f "${PGDATA}"/postgresqlFullBackup.dump
