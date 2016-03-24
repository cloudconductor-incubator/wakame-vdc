#!/bin/bash
#
# requires:
#   bash
#

## include files

## variables

declare instance_ipaddr=

function needs_vif() { true; }
function needs_secg() { true; }

vifs_eth0_network_id=${vifs_eth0_network_id:-nw-demo1}
ssh_user=${ssh_user:-root}
blank_volume_size=${blank_volume_size:-10M}

## functions

function remote_sudo() {
  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-'EOS'
	case "${UID}" in
	0) ;;
	*) echo sudo ;;
	esac
	EOS
}

function blank_dev_serial() {
  ssh -t ${ssh_user}@${instance_ipaddr} -i ${ssh_key_pair_path} <<-EOS
	fgrep -r ${volume_uuid} /sys/block/*/serial
	EOS
}

function blank_dev_path() {
  dev_name=$(blank_dev_serial | awk -F/ '{print $4}')
  [[ -n "${dev_name}" ]] && echo /dev/${dev_name}
}

### instance

function render_vif_table() {
  cat <<-EOS
	{"eth0":{"index":"0","network":"${vifs_eth0_network_id}","security_groups":"${security_group_uuid}"}}
	EOS
}

function render_secg_rule() {
  cat <<-EOS
	icmp:-1,-1,ip4:0.0.0.0/0
	tcp:22,22,ip4:0.0.0.0/0
	EOS
}

function after_create_instance() {
  instance_ipaddr=$(run_cmd instance show ${instance_uuid} | hash_value address)
  wait_for_network_to_be_ready ${instance_ipaddr}
  wait_for_sshd_to_be_ready    ${instance_ipaddr}
}

