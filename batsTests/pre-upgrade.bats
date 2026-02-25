#! /bin/bash
# Bind an unbound BATS variables that fail all tests when combined with 'set -o nounset'
export BATS_TEST_START_TIME="0"
export BATSLIB_FILE_PATH_REM=""
export BATSLIB_FILE_PATH_ADD=""

load '/workspace/target/bats_libs/bats-support/load.bash'
load '/workspace/target/bats_libs/bats-assert/load.bash'
load '/workspace/target/bats_libs/bats-mock/load.bash'
load '/workspace/target/bats_libs/bats-file/load.bash'

setup() {
  pg_dumpall="$(mock_create)"
  doguctl="$(mock_create)"
  gosu="$(mock_create)"
  export pg_dumpall
  export doguctl
  export gosu
  export PATH="${BATS_TMPDIR}:${PATH}"
  export PGDATA="/var/lib/postgresql"
  ln -s "${pg_dumpall}" "${BATS_TMPDIR}/pg_dumpall"
  ln -s "${doguctl}" "${BATS_TMPDIR}/doguctl"
  ln -s "${doguctl}" "${BATS_TMPDIR}/gosu"
}

teardown() {
  rm "${BATS_TMPDIR}/pg_dumpall"
  rm "${BATS_TMPDIR}/doguctl"
  rm "${BATS_TMPDIR}/gosu"
}

@test "runPreUpgrade should do nothing on equal versions" {
  source /workspace/resources/pre-upgrade.sh

  run runPreUpgrade "1.0.0-1" "1.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${pg_dumpall}")" "0"
  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
  assert_line 'FROM and TO versions are the same; Exiting...'
}

@test "runPreUpgrade should just set local_state on minor upgrade" {
  source /workspace/resources/pre-upgrade.sh
  mock_set_status "${doguctl}" 0

  run runPreUpgrade "100.0.0-1" "100.1.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${pg_dumpall}")" "0"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_line 'Set registry flag so startup script waits for post-upgrade to finish...'
}

@test "runPreUpgrade should set local_state and save dump on major upgrade" {
  source /workspace/resources/pre-upgrade.sh
  mock_set_status "${doguctl}" 0
  mock_set_status "${pg_dumpall}" 0
  mock_set_status "${gosu}" 0

  run runPreUpgrade "1.0.0-1" "2.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
  assert_line "Creating lock file /var/lib/postgresql/backup/backup.lock..."
  assert_line "Successfully created backup /var/lib/postgresql/backup/full_backup_$(date +%F).sql"
  assert_line 'Set registry flag so startup script waits for post-upgrade to finish...'
}
