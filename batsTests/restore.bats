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
  doguctl="$(mock_create)"
  psql="$(mock_create)"
  export doguctl
  export psql
  export PATH="${BATS_TMPDIR}:${PATH}"

  ln -sf "${doguctl}" "${BATS_TMPDIR}/doguctl"
  ln -sf "${psql}" "${BATS_TMPDIR}/psql"

  export BACKUP_FILE="${BATS_TMPDIR}/full_backup.sql"
  printf 'DROP ROLE IF EXISTS postgres;\nCREATE ROLE postgres;\nALTER ROLE postgres WITH SUPERUSER;\nCREATE ROLE redmine;\n' > "${BACKUP_FILE}"
}

teardown() {
  rm -f "${BACKUP_FILE}"
  rm -f "${BATS_TMPDIR}/doguctl" "${BATS_TMPDIR}/psql"
}

@test "runRestore should skip if no backup is configured" {
  mock_set_output "${doguctl}" "empty" 1

  run /workspace/resources/restore.sh

  assert_success
  assert_line "No backup found in config, skipping restore..."
  assert_equal "$(mock_get_call_num "${psql}")" "0"
}

@test "runRestore should fail if the backup file is missing" {
  mock_set_output "${doguctl}" "${BATS_TMPDIR}/missing.sql" 1

  run /workspace/resources/restore.sh

  assert_failure
  assert_line --partial "not found on disk!"
  assert_equal "$(mock_get_call_num "${psql}")" "0"
}

@test "runRestore should restore the dump without the superuser and clean up afterwards" {
  mock_set_output "${doguctl}" "${BACKUP_FILE}" 1
  mock_set_output "${doguctl}" "postgres" 3

  run /workspace/resources/restore.sh

  assert_success
  assert_equal "$(mock_get_call_args "${psql}" 1)" "-v ON_ERROR_STOP=1 -U postgres"
  assert_equal "$(mock_get_call_args "${doguctl}" 2)" "state upgrading"
  assert_equal "$(mock_get_call_args "${doguctl}" 4)" "config --rm migration_backup_path"
  # the dogu state is set by startup.sh once the database accepts connections
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
  assert_file_not_exists "${BACKUP_FILE}"
}

@test "runRestore should keep flag and backup if psql fails" {
  mock_set_output "${doguctl}" "${BACKUP_FILE}" 1
  mock_set_output "${doguctl}" "postgres" 3
  mock_set_status "${psql}" 3 1

  run /workspace/resources/restore.sh

  assert_failure
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
  assert_file_exists "${BACKUP_FILE}"
}
