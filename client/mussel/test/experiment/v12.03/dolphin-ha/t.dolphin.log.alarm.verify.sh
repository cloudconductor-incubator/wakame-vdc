#!/bin/bash
#
# requires:
#  bash
#  cat, ssh-keygen, ping, rm
#

## include files
. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh
. ${BASH_SOURCE[0]%/*}/helper_dolphin.sh

## variables
sleep_sec=${sleep_sec:-240}

## functions

function setUp() {
  load_instance_file
  instance_ipaddr=$(cached_instance_param ${instance_uuid} | ydump | yfind ':vif:/0/:ipv4:/:address:')
}

## step

# verification log alarm.
#
# 1. write match pattern text to /var/log/messages.
# 2. wait time ${sleep_sec} min.
# 3. check the event API.
function test_log_alarm_verification() {
  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	for i in {0..2}; do sudo bash -c "echo 'error' >> /var/log/messages"; done;
	EOS
  assertEquals 0 $?

  sleep ${sleep_sec}

  start_time=$(date +%Y%m%d) run_cmd event index | $(json_sh) | grep ${instance_uuid}
  assertEquals 0 $?
}

## shunit2
. ${shunit2_file}

