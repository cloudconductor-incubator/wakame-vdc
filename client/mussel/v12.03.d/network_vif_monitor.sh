# -*-Shell-script-*-
#
# 12.03
#

. ${BASH_SOURCE[0]%/*}/base.sh

task_index() {
  local namespace=$1 cmd=$2 uuid=$3
  [[ -n "${namespace}" ]] || { echo "[ERROR] 'namespace' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${cmd}"       ]] || { echo "[ERROR] 'cmd' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${uuid}"      ]] || { echo "[ERROR] 'uuid' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  call_api -X GET \
  $(base_uri)/network_vifs/${uuid}/monitors.$(suffix)
}

task_show() {
  local namespace=$1 cmd=$2 uuid=$3 monitor_id=$4
  [[ -n "${namespace}"  ]] || { echo "[ERROR] 'namespace' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${cmd}"        ]] || { echo "[ERROR] 'cmd' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${uuid}"       ]] || { echo "[ERROR] 'uuid' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${monitor_id}" ]] || { echo "[ERROR] 'monitor_id' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  call_api -X GET \
  $(base_uri)/network_vifs/${uuid}/monitors/${monitor_id}.$(suffix)
}

task_create() {
  local namespace=$1 cmd=$2 uuid=$3
  [[ -n "${namespace}"  ]] || { echo "[ERROR] 'namespace' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${cmd}"        ]] || { echo "[ERROR] 'cmd' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${uuid}"       ]] || { echo "[ERROR] 'uuid' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  call_api -X POST $(urlencode_data \
    $(add_param enabled string) \
    $(add_param title   string) \
    $(add_param params    hash) \
   ) \
  $(base_uri)/network_vifs/${uuid}/monitors.$(suffix)
}

task_update() {
  local namespace=$1 cmd=$2 uuid=$3 monitor_id=$4
  [[ -n "${namespace}"  ]] || { echo "[ERROR] 'namespace' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${cmd}"        ]] || { echo "[ERROR] 'cmd' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${uuid}"       ]] || { echo "[ERROR] 'uuid' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${monitor_id}" ]] || { echo "[ERROR] 'monitor_id' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  call_api -X PUT $(urlencode_data \
    $(add_param enabled string) \
    $(add_param title   string) \
    $(add_param params    hash) \
   ) \
   $(base_uri)/network_vifs/${uuid}/monitors/${monitor_id}.$(suffix)
}

task_destroy() {
  local namespace=$1 cmd=$2 uuid=$3 monitor_id=$4
  [[ -n "${namespace}"  ]] || { echo "[ERROR] 'namespace' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${cmd}"        ]] || { echo "[ERROR] 'cmd' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${uuid}"       ]] || { echo "[ERROR] 'uuid' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  [[ -n "${monitor_id}" ]] || { echo "[ERROR] 'monitor_id' is empty (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }

  call_api -X DELETE \
  $(base_uri)/network_vifs/${uuid}/monitors/${monitor_id}.$(suffix)
}

