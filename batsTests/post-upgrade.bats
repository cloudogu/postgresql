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
  export doguctl
  export PATH="${BATS_TMPDIR}:${PATH}"
  mkdir ${BATS_TMPDIR}/postgresql_bats
  export PGDATA="${BATS_TMPDIR}/postgresql_bats"

  ln -s "${doguctl}" "${BATS_TMPDIR}/doguctl"
}

teardown() {
  /bin/rm "${BATS_TMPDIR}/doguctl"
  /bin/rm -r "${BATS_TMPDIR}/postgresql_bats"
}

@test "versionXLessOrEqualThanY() should return true for versions less than or equal to another" {
  source /workspace/resources/post-upgrade.sh

  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.1.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.2-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "1.0.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.1.0-1" "1.1.0-2"
  assert_success
  run versionXLessOrEqualThanY "1.0.2-1" "1.0.2-2"
  assert_success
  run versionXLessOrEqualThanY "1.2.3-4" "1.2.3-4"
  assert_success
  run versionXLessOrEqualThanY "1.2.3-4" "1.2.3-5"
  assert_success

  run versionXLessOrEqualThanY "1.0.0-1" "2.0.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.1.0-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.0.1-1"
  assert_success
  run versionXLessOrEqualThanY "1.0.0-1" "2.1.1-1"
  assert_success
  run versionXLessOrEqualThanY "5.1.3-1" "5.1.3-1"
  assert_success
}

@test "versionXLessOrEqualThanY() should return false for versions greater than another" {
  source /workspace/resources/post-upgrade.sh

  run versionXLessOrEqualThanY "0.0.0-10" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-0" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.1.0-1" "0.0.0-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.0.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-1" "0.9.9-9"
  assert_failure
  run versionXLessOrEqualThanY "1.0.0-0" "0.9.9-9"
  assert_failure

  run versionXLessOrEqualThanY "1.2.3-4" "0.1.2-3"
  assert_failure
  run versionXLessOrEqualThanY "1.2.3-5" "0.1.2-3"
  assert_failure

  run versionXLessOrEqualThanY "2.0.0-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.1.0-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.0.1-1" "1.0.0-1"
  assert_failure
  run versionXLessOrEqualThanY "2.1.1-1" "1.0.0-1"
  assert_failure
}

@test "runPostUpgrade should exit early if no version change" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  startPostgresql() {
    echo "startPostgresql is mocked"
  }

  mock_set_output "${doguctl}" "true" 1
  mock_set_status "${doguctl}" 0 2
  run runPostUpgrade "1.0.0-1" "1.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "2"
  assert_line "startPostgresql is mocked"
  assert_line "FROM and TO versions are the same; Exiting..."
}

@test "runPostUpgrade should also restrict stat visibility if no version change" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  startPostgresql() {
    echo "startPostgresql is mocked"
  }
  restrictStatVisibility() {
    echo "restrictStatVisibility is mocked"
  }

  mock_set_output "${doguctl}" "false" 1
  mock_set_status "${doguctl}" 0 2
  run runPostUpgrade "1.0.0-1" "1.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "2"
  assert_line "startPostgresql is mocked"
  assert_line "Postgresql stats might be visible outside of their intended scope. Restricting stat visibility..."
  assert_line "restrictStatVisibility is mocked"
  assert_line "FROM and TO versions are the same; Exiting..."
}

@test "runPostUpgrade should reindexAllDatabases on version upgrade" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  startPostgresql() {
    echo "startPostgresql is mocked"
  }
  reindexAllDatabases() {
    echo "reindexAllDatabases is mocked"
  }
  versionXLessOrEqualThanY() {
    echo "versionXLessOrEqualThanY is mocked"
    return 0
  }
  killPostgresql() {
    echo "killPostgresql is mocked"
  }

  mock_set_output "${doguctl}" "true" 1
  mock_set_output "${doguctl}" "true" 2
  mock_set_status "${doguctl}" 0 3
  run runPostUpgrade "1.0.0-1" "2.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
  assert_line "startPostgresql is mocked"
  assert_line "Postgresql version changed. Reindexing all databases..."
  assert_line "reindexAllDatabases is mocked"
  assert_line "versionXLessOrEqualThanY is mocked"
  assert_line "killPostgresql is mocked"
}

@test "runPostUpgrade should restrict stats visibility if not already restricted" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  startPostgresql() {
    echo "startPostgresql is mocked"
  }
  restrictStatVisibility() {
    echo "restrictStatVisibility is mocked"
  }
  reindexAllDatabases() {
    echo "reindexAllDatabases is mocked"
  }
  versionXLessOrEqualThanY() {
    echo "versionXLessOrEqualThanY is mocked"
    return 0
  }
  killPostgresql() {
    echo "killPostgresql is mocked"
  }

  # stats not yet restricted
  mock_set_output "${doguctl}" "false" 1
  mock_set_output "${doguctl}" "true" 2
  mock_set_status "${doguctl}" 0 3
  run runPostUpgrade "1.0.0-1" "2.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
  assert_line "startPostgresql is mocked"
  assert_line "Postgresql stats might be visible outside of their intended scope. Restricting stat visibility..."
  assert_line "restrictStatVisibility is mocked"
  assert_line "reindexAllDatabases is mocked"
  assert_line "versionXLessOrEqualThanY is mocked"
  assert_line "killPostgresql is mocked"
}

@test "runPostUpgrade should restore db dump if dump file exists" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  prepareForBackup() {
    echo "prepareForBackup is mocked"
    isBackupAvailable=true
  }
  startPostgresql() {
    echo "startPostgresql is mocked"
  }
  restoreBackup() {
    echo "restoreBackup is mocked"
  }
  reindexAllDatabases() {
    echo "reindexAllDatabases is mocked"
  }
  versionXLessOrEqualThanY() {
    echo "versionXLessOrEqualThanY is mocked"
    return 0
  }
  killPostgresql() {
    echo "killPostgresql is mocked"
  }

  tmpfile="${PGDATA}/postgresqlFullBackup.dump"
  touch "$tmpfile"  # Create the file


  # stats not yet restricted
  mock_set_output "${doguctl}" "true" 1
  mock_set_output "${doguctl}" "true" 2
  mock_set_status "${doguctl}" 0 3
  run runPostUpgrade "1.0.0-1" "2.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
  assert_line "prepareForBackup is mocked"
  assert_line "startPostgresql is mocked"
  assert_line "restoreBackup is mocked"
  assert_line "reindexAllDatabases is mocked"
  assert_line "versionXLessOrEqualThanY is mocked"
  assert_line "killPostgresql is mocked"

  # Cleanup: Remove the file
  rm "$tmpfile"
}

@test "runPostUpgrade should migrateConstraintsOnPartitionedTables if not yet migrated" {
  source /workspace/resources/post-upgrade.sh

  # Mock the functions
  startPostgresql() {
    echo "startPostgresql is mocked"
  }
  reindexAllDatabases() {
    echo "reindexAllDatabases is mocked"
  }
  versionXLessOrEqualThanY() {
    echo "versionXLessOrEqualThanY is mocked"
    return 0
  }
  migrateConstraintsOnPartitionedTables() {
    echo "migrateConstraintsOnPartitionedTables is mocked"
  }
  killPostgresql() {
    echo "killPostgresql is mocked"
  }

  mock_set_output "${doguctl}" "true" 1
  mock_set_output "${doguctl}" "false" 2
  mock_set_status "${doguctl}" 0 3
  run runPostUpgrade "1.0.0-1" "2.0.0-1"

  assert_success
  assert_equal "$(mock_get_call_num "${doguctl}")" "3"
  assert_line "startPostgresql is mocked"
  assert_line "Postgresql version changed. Reindexing all databases..."
  assert_line "reindexAllDatabases is mocked"
  assert_line "versionXLessOrEqualThanY is mocked"
  assert_line "migrateConstraintsOnPartitionedTables is mocked"
  assert_line "killPostgresql is mocked"
}
