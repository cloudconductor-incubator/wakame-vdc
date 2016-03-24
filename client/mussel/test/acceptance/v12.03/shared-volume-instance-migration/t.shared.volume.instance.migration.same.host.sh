#!/bin/bash
#
#
#
#

## include files

. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh

## variables
launch_host_node=${launch_host_node:-hn-demo1}
migration_host_node=${migration_host_node:-hn-demo2}
blank_volume_size=${blank_volume_size:-10M}

## hook functions

### step

# API test for shared volume instance migration to same host.
#
# 1. boot shared volume instance 1.
# 2. boot shared volume instance 2.
# 3. migration the instance 1.
# 4. migration the instance 2.
# 5. check the process 1.
# 6. check the process 2.
# 7. migration the instance 1.
# 8. migration the instance 2.
# 9. check the process 1.
# 10. check the process 2.
# 11. terminate the instance 1.
# 12. terminate the instance 2.
function test_migration_shared_volume_instance_same_host(){
  # boot shared volume instance 1.
  local host_node_id=${launch_host_node}
  create_instance

  # setup instance 1.
  local instance_uuid1=${instance_uuid}
  local instance_ipaddr1=${instance_ipaddr}

  # boot shared volume instance 2.
  create_instance

  # setup instance 2
  local instance_uuid2=${instance_uuid}
  local instance_ipaddr2=${instance_ipaddr}

  # bind sleep process 1
  local instance_ipaddr=${instance_ipaddr1}
  bind_sleep_process
  assertEquals 0 $?

  # sleep process id 1
  process_id1=$(sleep_process_id)
  [[ -n "${process_id1}" ]]
  assertEquals 0 $?
  echo "sleep process id: ${process_id1}"

  # bind sleep process 2
  local instance_ipaddr=${instance_ipaddr2}
  bind_sleep_process
  assertEquals 0 $?

  # sleep process id 2
  process_id2=$(sleep_process_id)
  [[ -n "${process_id2}" ]]
  assertEquals 0 $?
  echo "sleep process id: ${process_id2}"

  # migration the instance 1.
  host_node_id=${migration_host_node} run_cmd instance move ${instance_uuid1} >/dev/null
  assertEquals 0 $?

  # migration the instance 2.
  host_node_id=${migration_host_node} run_cmd instance move ${instance_uuid2} >/dev/null
  assertEquals 0 $?

  # wait migration
  retry_until "document_pair? instance ${instance_uuid1} state running"
  assertEquals 0 $?

  retry_until "document_pair? instance ${instance_uuid2} state running"
  assertEquals 0 $?

  # check the process1.
  local instance_ipaddr=${instance_ipaddr1}
  new_process_id1=$(sleep_process_id)
  [[ -n "${new_process_id1}" ]]
  assertEquals 0 $?
  echo "new sleep process id: ${new_process_id1}"
  assertEquals ${process_id1} ${new_process_id1}

  # check the process2.
  local instance_ipaddr=${instance_ipaddr2}
  new_process_id2=$(sleep_process_id)
  [[ -n "${new_process_id2}" ]]
  assertEquals 0 $?
  echo "new sleep process id: ${new_process_id2}"
  assertEquals ${process_id2} ${new_process_id2}

  # migration the instance 1.
  host_node_id=${launch_host_node} run_cmd instance move ${instance_uuid1} >/dev/null
  assertEquals 0 $?

  # migration the instance 2.
  host_node_id=${launch_host_node} run_cmd instance move ${instance_uuid2} >/dev/null
  assertEquals 0 $?

  # wait migration
  retry_until "document_pair? instance ${instance_uuid1} state running"
  assertEquals 0 $?

  retry_until "document_pair? instance ${instance_uuid2} state running"
  assertEquals 0 $?

  # check the process1.
  local instance_ipaddr=${instance_ipaddr1}
  new_process_id1=$(sleep_process_id)
  [[ -n "${new_process_id1}" ]]
  assertEquals 0 $?
  echo "new sleep process id: ${new_process_id1}"
  assertEquals ${process_id1} ${new_process_id1}

  # check the process2.
  local instance_ipaddr=${instance_ipaddr2}
  new_process_id2=$(sleep_process_id)
  [[ -n "${new_process_id2}" ]]
  assertEquals 0 $?
  echo "new sleep process id: ${new_process_id2}"
  assertEquals ${process_id2} ${new_process_id2}

  # terminate the instance 1.
  run_cmd instance destroy ${instance_uuid1} >/dev/null
  assertEquals 0 $?

  # terminate the instance 2.
  local instance_uuid=${instance_uuid2}
  destroy_instance

}

## shunit2

. ${shunit2_file}

