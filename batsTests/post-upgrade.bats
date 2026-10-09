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

  # Mocks für Systembefehle
  echo "#!/bin/bash" > "${BATS_TMPDIR}/chown"
  chmod +x "${BATS_TMPDIR}/chown"
  echo "#!/bin/bash" > "${BATS_TMPDIR}/gosu"
  echo "shift 2; exec \"\$@\"" >> "${BATS_TMPDIR}/gosu"
  chmod +x "${BATS_TMPDIR}/gosu"

  # Fake Filesystem
  export FAKE_ROOT="${BATS_TMPDIR}/fake_root"
  export PG_BASE_DIR="${FAKE_ROOT}/var/lib/postgresql"
  export PGDATA="${PG_BASE_DIR}/14/data"
  export PG_MAJOR="14"
  mkdir -p "${PGDATA}" "${PG_BASE_DIR}/backup"

  export POST_UPGRADE_LOCK_FILE="${BATS_TMPDIR}/post-upgrade.lock"
}

teardown() {
  rm -rf "${FAKE_ROOT}"
  rm -f "${BATS_TMPDIR}/post-upgrade-patched.sh"
  rm -f "${BATS_TMPDIR}/util.sh"
  rm -f "${BATS_TMPDIR}/post-upgrade-mocks.sh"
  rm -f "${POST_UPGRADE_LOCK_FILE}"
}

# write_step_mocks replaces all steps of the post-upgrade with functions which only print their name.
# The file is sourced after the patched script so the mocks can be used in a subshell with errexit.
write_step_mocks() {
  cat > "${BATS_TMPDIR}/post-upgrade-mocks.sh" <<'EOF'
id() { echo "1000"; }
prepareForRestore() { echo "STEP prepareForRestore"; }
initDatabase() { echo "STEP initDatabase"; }
startPostgresql() { echo "STEP startPostgresql"; }
restoreBackup() { echo "STEP restoreBackup"; }
rotateSuperuserPassword() { echo "STEP rotateSuperuserPassword"; }
runMigrations() { echo "STEP runMigrations"; }
stopPostgresql() { echo "STEP stopPostgresql"; }
EOF
}

# run_post_upgrade executes runPostUpgrade in a subshell with errexit, because bats' run disables it.
# Additional function overrides can be passed as first argument.
run_post_upgrade() {
  local overrides="${1:-}"
  run bash -c "source '${BATS_TMPDIR}/post-upgrade-patched.sh'; source '${BATS_TMPDIR}/post-upgrade-mocks.sh'; ${overrides}
    set -o errexit; runPostUpgrade 14.18-3 14.24-3"
}

load_script_safely() {
  # create mock for util.sh
  touch "${BATS_TMPDIR}/util.sh"

  # We need to patch the script: remove hardcoded source of entrypoint
  sed 's|source "/usr/local/bin/docker-entrypoint.sh"|# entrypoint ignored|g' \
      /workspace/resources/post-upgrade.sh > "${BATS_TMPDIR}/post-upgrade-patched.sh"

  # load patched file
  source "${BATS_TMPDIR}/post-upgrade-patched.sh"
}

@test "runPostUpgrade should exit early if versions match" {
  load_script_safely
  mock_set_status "${doguctl}" 0 1

  run runPostUpgrade "14.1-1" "14.1-1"

  assert_success
  assert_line --partial "FROM and TO versions are the same"
}

@test "runPostUpgrade should skip and exit 0 when local_state is not upgrading" {
  load_script_safely
  write_step_mocks
  # local_state has already been removed by a previous, successful post-upgrade run.
  mock_set_output "${doguctl}" "empty" 1

  run_post_upgrade

  assert_success
  assert_line --partial "post-upgrade already completed"
  refute_line --partial "STEP"
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}

@test "runPostUpgrade should fix permissions and switch to the postgres user when run as root" {
  load_script_safely
  write_step_mocks
  echo 'echo "chown $*"' >> "${BATS_TMPDIR}/chown"
  printf '#!/bin/bash\necho "gosu $*"\n' > "${BATS_TMPDIR}/gosu"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2

  run_post_upgrade 'id() { echo "0"; }'

  assert_success
  assert_line "chown -R postgres /var/lib/postgresql/"
  assert_line --partial "gosu postgres"
  refute_line --partial "STEP"
  assert_equal "$(mock_get_call_num "${doguctl}")" "2"
}

@test "runPostUpgrade should restore the backup before removing local_state" {
  load_script_safely
  write_step_mocks
  touch "${PG_BASE_DIR}/backup/dump.sql"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  mock_set_output "${doguctl}" "${PG_BASE_DIR}/backup/dump.sql" 3

  run_post_upgrade

  assert_success
  assert_equal "$(echo "${output}" | grep "^STEP" | tr '\n' ' ')" \
    "STEP prepareForRestore STEP initDatabase STEP startPostgresql STEP restoreBackup STEP rotateSuperuserPassword STEP runMigrations STEP stopPostgresql "
  assert_equal "$(mock_get_call_args "${doguctl}" 4)" "config --rm local_state"
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
  assert_line "Postgresql post-upgrade done"
}

@test "runPostUpgrade should keep local_state if the restore fails" {
  load_script_safely
  write_step_mocks
  touch "${PG_BASE_DIR}/backup/dump.sql"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  mock_set_output "${doguctl}" "${PG_BASE_DIR}/backup/dump.sql" 3

  run_post_upgrade 'restoreBackup() { echo "STEP restoreBackup"; return 1; }'

  assert_failure
  assert_line "STEP restoreBackup"
  refute_line "STEP runMigrations"
  refute_line "Postgresql post-upgrade done"
  # local_state is not removed, so startup.sh keeps waiting
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
}

@test "runPostUpgrade should keep the existing data if the backup file is missing" {
  load_script_safely
  write_step_mocks
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  mock_set_output "${doguctl}" "${PG_BASE_DIR}/backup/missing.sql" 3

  run_post_upgrade

  assert_failure
  assert_line --partial "ERROR: Backup file ${PG_BASE_DIR}/backup/missing.sql not found on disk!"
  refute_line --partial "STEP"
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
}

@test "runPostUpgrade should abort if another post-upgrade holds the lock" {
  load_script_safely
  write_step_mocks
  echo 'echo "chown $*"' >> "${BATS_TMPDIR}/chown"
  printf '#!/bin/bash\necho "gosu $*"\n' > "${BATS_TMPDIR}/gosu"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  exec 8>"${POST_UPGRADE_LOCK_FILE}"
  flock -n 8

  run_post_upgrade 'id() { echo "0"; }'

  exec 8>&-
  assert_failure
  assert_line --partial "ERROR: Another post-upgrade is still running"
  refute_line --partial "chown"
  refute_line --partial "gosu"
  refute_line --partial "STEP"
  assert_equal "$(mock_get_call_num "${doguctl}")" "2"
}

@test "runPostUpgrade should skip if database is uninitialized" {
  load_script_safely
  write_step_mocks

  rm -f "${PGDATA}/PG_VERSION"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  mock_set_output "${doguctl}" "empty" 3

  run_post_upgrade

  assert_success
  assert_line "PostgreSQL does not seem to be initialized, skip post upgrade..."
  refute_line --partial "STEP"
  assert_equal "$(mock_get_call_args "${doguctl}" 4)" "config --rm local_state"
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
}

@test "runPostUpgrade should execute init scripts" {
  id() { echo "1000"; }
  export -f id
  load_script_safely

  startPostgresql(){
    echo "mock startPostgresql"
  }

  stopPostgresql(){
    echo "mock stopPostgresql"
  }

  runMigrations(){
    echo "INIT_SCRIPT_EXECUTED"
  }

  echo "14" > "${PGDATA}/PG_VERSION"
  mock_set_output "${doguctl}" "upgrading" 1
  mock_set_output "${doguctl}" "postgres" 2
  mock_set_output "${doguctl}" "empty" 3

  run runPostUpgrade "14.1-1" "14.2-1"

  assert_success
  assert_line "Postgresql post-upgrade done"
}


@test "rotateSuperuserPassword guard suppresses rotation via rotation flag" {
  # arrange
  load_script_safely
  mock_set_output "${doguctl}" "true"

  # act
  run rotateSuperuserPassword

  # assert
  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
  assert_line "Superuser password has already been rotated; skipping"
}

@test "rotateSuperuserPassword() should rotate superuser password if not rotated before" {
  # arrange doguctl
  load_script_safely
  mock_set_output "${doguctl}" "false" 1
  mock_set_output "${doguctl}" "testusername" 2
  mock_set_output "${doguctl}" "random123" 3

  # arrange psql
  local psql_mock_call_args
  psql_mock_call_args="--variable=ON_ERROR_STOP=1"
  psql_mock_call_args+=" --username=testusername"
  psql_mock_call_args+=" --command=ALTER USER \"testusername\" WITH PASSWORD 'random123';"
  
  # act
  run rotateSuperuserPassword

  # assert
  assert_success
  assert_equal "$(mock_get_call_args "${doguctl}" 1)" "config --default false password_rotated"
  assert_line "Rotating superuser password..."
  assert_equal "$(mock_get_call_args "${doguctl}" 2)" "config --default postgres user"
  assert_equal "$(mock_get_call_args "${doguctl}" 3)" "random"
  assert_equal "$(mock_get_call_args "${doguctl}" 4)" "config --encrypted password random123"
  assert_equal "$(mock_get_call_args "${psql}" 1)" "${psql_mock_call_args}"
  assert_equal "$(mock_get_call_args "${doguctl}" 5)" "config password_rotated true"
  assert_line "Superuser password rotated"

  assert_equal "$(mock_get_call_num "${doguctl}")" "5"
  assert_equal "$(mock_get_call_num "${psql}")" "1"
}

@test "rotateSuperuserPassword() should not set the flag if the database update fails" {
  # arrange
  load_script_safely
  mock_set_output "${doguctl}" "false" 1
  mock_set_output "${doguctl}" "testusername" 2
  mock_set_output "${doguctl}" "random123" 3
  mock_set_status "${psql}" 1 1 # psql fails

  # act
  # run seems to disable errexit so the psql failure would be ingored and flag "password_rotated" set true
  # Another subshell with errexit validates cancelation.
  run bash -c "source '${BATS_TMPDIR}/post-upgrade-patched.sh'; set -o errexit; rotateSuperuserPassword"

  # assert
  assert_failure
  assert_line "Rotating superuser password..."
  assert_equal "$(mock_get_call_args "${doguctl}" 4)" "config --encrypted password random123"
  assert_equal "$(mock_get_call_num "${psql}")" "1"

  # password is set in config, flag "password_rotated" is NOT.
  # Only four doguctl calls.
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
  refute_line "Superuser password rotated"
}

@test "rotateSuperuserPassword() should not touch the database if writing the config fails" {
  # arrange
  load_script_safely
  mock_set_output "${doguctl}" "false" 1
  mock_set_output "${doguctl}" "testusername" 2
  mock_set_output "${doguctl}" "random123" 3
  # the fourth call is the one writing the new password into the config
  mock_set_status "${doguctl}" 1 4

  # act
  run bash -c "source '${BATS_TMPDIR}/post-upgrade-patched.sh'; set -o errexit; rotateSuperuserPassword"

  # assert
  assert_failure
  assert_line "Rotating superuser password..."
  # If password could not be saved to config, "ALTER ... PASSWORD" should not be called
  assert_equal "$(mock_get_call_num "${psql}")" "0"
  assert_equal "$(mock_get_call_num "${doguctl}")" "4"
  refute_line "Superuser password rotated"
}
