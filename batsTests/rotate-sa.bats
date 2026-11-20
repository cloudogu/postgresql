#! /bin/bash
# Bind an unbound BATS variables that fail all tests when combined with 'set -o nounset'
export BATS_TEST_START_TIME="0"
export BATSLIB_FILE_PATH_REM=""
export BATSLIB_FILE_PATH_ADD=""

load '/workspace/target/bats_libs/bats-support/load.bash'
load '/workspace/target/bats_libs/bats-assert/load.bash'
load '/workspace/target/bats_libs/bats-mock/load.bash'
load '/workspace/target/bats_libs/bats-file/load.bash'

# run --separate-stderr is needed to check that stdout only contains the line cesapp parses
bats_require_minimum_version 1.5.0

setup() {
  doguctl="$(mock_create)"
  psql="$(mock_create)"
  export doguctl
  export psql
  export PATH="${BATS_TMPDIR}:${PATH}"

  ln -sf "${doguctl}" "${BATS_TMPDIR}/doguctl"
  ln -sf "${psql}" "${BATS_TMPDIR}/psql"

  # psql receives the ALTER statement via stdin and the log settings via PGOPTIONS; the side effect stores both
  PSQL_STDIN="${BATS_TMPDIR}/psql_stdin"
  PSQL_PGOPTIONS="${BATS_TMPDIR}/psql_pgoptions"
  export PSQL_STDIN PSQL_PGOPTIONS
  rm -f "${PSQL_STDIN}" "${PSQL_PGOPTIONS}"
}

teardown() {
  rm -f "${BATS_TMPDIR}/doguctl" "${BATS_TMPDIR}/psql" "${PSQL_STDIN}" "${PSQL_PGOPTIONS}"
}

arrange_existing_user() {
  mock_set_output "${doguctl}" "postgres" 1
  mock_set_output "${doguctl}" "random123" 2
  mock_set_output "${psql}" "1" 1
  mock_set_side_effect "${psql}" "printf '%s' \"\${PGOPTIONS:-}\" > '${PSQL_PGOPTIONS}'; cat > '${PSQL_STDIN}'" 2
  # the real psql prints the command tag; the script must keep it away from stdout, because cesapp parses it
  mock_set_output "${psql}" "ALTER ROLE" 2
}

@test "rotate-sa.sh should fail with usage when no arguments are passed" {
  run --separate-stderr /workspace/resources/rotate-sa.sh

  assert_failure
  assert_output ""
  [[ "${stderr}" == *"usage rotate-sa.sh"* ]]
  assert_equal "$(mock_get_call_num "${psql}")" "0"
  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
}

@test "rotate-sa.sh should fail with usage when only one argument is passed" {
  run --separate-stderr /workspace/resources/rotate-sa.sh redmine

  assert_failure
  assert_output ""
  [[ "${stderr}" == *"usage rotate-sa.sh"* ]]
  assert_equal "$(mock_get_call_num "${psql}")" "0"
}

@test "rotate-sa.sh should refuse usernames that do not belong to the service without touching the database" {
  local username
  for username in "postgres" "redmine_5deimx'; DROP DATABASE redmine_5deimx" "redmine_5de" "redmine_5deimxx" "REDMINE_ABCDEF" "redmine-5deimx"; do
    run --separate-stderr /workspace/resources/rotate-sa.sh "${username}" redmine

    assert_failure
    assert_output ""
    [[ "${stderr}" == *"does not belong to service redmine"* ]]
  done

  assert_equal "$(mock_get_call_num "${psql}")" "0"
  assert_equal "$(mock_get_call_num "${doguctl}")" "0"
}

@test "rotate-sa.sh should refuse a username of another service with the same prefix" {
  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_x5deim red

  assert_failure
  [[ "${stderr}" == *"does not belong to service red"* ]]
  assert_equal "$(mock_get_call_num "${psql}")" "0"
}

@test "rotate-sa.sh should fail without changing a password when the user does not exist" {
  mock_set_output "${doguctl}" "postgres" 1
  mock_set_output "${psql}" "" 1

  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_5deimx redmine

  assert_failure
  assert_output ""
  [[ "${stderr}" == *"user redmine_5deimx does not exist"* ]]
  assert_equal "$(mock_get_call_args "${psql}" 1)" "-U postgres -tAc SELECT 1 FROM pg_roles WHERE rolname='redmine_5deimx';"
  assert_equal "$(mock_get_call_num "${psql}")" "1"
  # no new password is generated
  assert_equal "$(mock_get_call_num "${doguctl}")" "1"
}

@test "rotate-sa.sh should change the password and print it as the only line on stdout" {
  arrange_existing_user

  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_5deimx redmine

  assert_success
  assert_output "password: random123"
  assert_equal "${stderr}" ""
  assert_equal "$(mock_get_call_args "${doguctl}" 1)" "config user"
  assert_equal "$(mock_get_call_args "${doguctl}" 2)" "random"
  assert_equal "$(mock_get_call_num "${psql}")" "2"
  assert_equal "$(cat "${PSQL_STDIN}")" "ALTER USER redmine_5deimx WITH PASSWORD 'random123';"
}

@test "rotate-sa.sh should not pass the password as a command line argument to psql" {
  arrange_existing_user

  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_5deimx redmine

  assert_success
  assert_equal "$(mock_get_call_args "${psql}" 2)" "-v ON_ERROR_STOP=1 -U postgres"
}

@test "rotate-sa.sh should ignore additional service account params in front of the username" {
  arrange_existing_user

  run --separate-stderr /workspace/resources/rotate-sa.sh de_DE.UTF-8 redmine_5deimx redmine

  assert_success
  assert_output "password: random123"
  assert_equal "$(cat "${PSQL_STDIN}")" "ALTER USER redmine_5deimx WITH PASSWORD 'random123';"
}

@test "rotate-sa.sh should not print a password when the ALTER statement fails" {
  arrange_existing_user
  mock_set_status "${psql}" 3 2

  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_5deimx redmine

  assert_failure
  assert_output ""
  [[ "${stderr}" != *"random123"* ]]
}

@test "rotate-sa.sh should turn off every log setting that writes the statement with the password into the server log" {
  arrange_existing_user

  run --separate-stderr /workspace/resources/rotate-sa.sh redmine_5deimx redmine

  assert_success
  # PGOPTIONS applies the settings when psql connects, before the ALTER statement reaches the server
  assert_equal "$(cat "${PSQL_PGOPTIONS}")" "-c log_statement=none -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_min_error_statement=panic -c debug_print_parse=off -c debug_print_rewritten=off -c debug_print_plan=off"
}
