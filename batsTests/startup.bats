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
  export STARTUP_DIR=/workspace/resources
  export WORKDIR=/workspace
  netstat="$(mock_create)"
  export netstat
  export PATH="${BATS_TMPDIR}:${PATH}"
  ln -s "${netstat}" "${BATS_TMPDIR}/netstat"
}

teardown() {
  unset STARTUP_DIR
  unset WORKDIR
  rm "${BATS_TMPDIR}/netstat"
}

@test "create_hba() should use cidr 16 if the dogu is running in a k8s cluster" {
  mock_set_output "${netstat}" "Kernel-IP-Routentabelle
Ziel            Router          Genmask         Flags   MSS Fenster irtt Iface
192.168.179.0   0.0.0.0         255.255.255.0   U         0 0          0 wlp0s20f3"

  source /workspace/resources/startup.sh
  local POD_NAMESPACE
  export POD_NAMESPACE="ecosystem"

  run create_hba

  assert_success
  assert_equal "$(mock_get_call_num "${netstat}")" "1"
  assert_line '# generated, do not override'
  assert_line '# "local" is for Unix domain socket connections only'
  assert_line 'local   all             all                                     trust'
  assert_line '# IPv4 local connections:'
  assert_line 'host    all             all             127.0.0.1/32            trust'
  assert_line '# IPv6 local connections:'
  assert_line 'host    all             all             ::1/128                 trust'
  assert_line '# container networks'
  assert_line "host    all             all             192.168.179.0/16          password"
}

@test "create_hba() should use regular cidr if the dogu is not running in a k8s cluster" {
  mock_set_output "${netstat}" "Kernel-IP-Routentabelle
Ziel            Router          Genmask         Flags   MSS Fenster irtt Iface
192.168.179.0   0.0.0.0         255.255.255.0   U         0 0          0 wlp0s20f3"

  source /workspace/resources/startup.sh

  run create_hba

  assert_success
  assert_equal "$(mock_get_call_num "${netstat}")" "1"
  assert_line '# generated, do not override'
  assert_line '# "local" is for Unix domain socket connections only'
  assert_line 'local   all             all                                     trust'
  assert_line '# IPv4 local connections:'
  assert_line 'host    all             all             127.0.0.1/32            trust'
  assert_line '# IPv6 local connections:'
  assert_line 'host    all             all             ::1/128                 trust'
  assert_line '# container networks'
  assert_line "host    all             all             192.168.179.0/24          password"
}
