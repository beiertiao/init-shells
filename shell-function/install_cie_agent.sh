#!/bin/bash
set -ex

this="${BASH_SOURCE-$0}"
bin=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
if [[ -f "${bin}/cie_config.sh" ]]; then
  . ${bin}/cie_config.sh
else
  echo "ERROR: Cannot execute ${bin}/cie_config.sh." 2>&1
  exit 1
fi

echo -e "############ install cie agent ###################\n"


if [ x"$ADD_NEW_HOST" = x"1" ]; then
  exec_cmd all "sudo systemctl stop ambari-agent || true"
  exec_cmd all "sudo yum remove -y ambari-agent >/dev/null || true"
  exec_cmd all "sudo yum install -y ambari-agent > /dev/null"
  copy_file all "${CURR_PATH}/../config/public_hostname.sh" "/tmp/"
  exec_cmd all "sudo mv /tmp/public_hostname.sh /var/lib/ambari-agent/"
  sudo cp -f /etc/ambari-agent/conf/ambari-agent.ini /tmp
  copy_file all "/tmp/ambari-agent.ini" "/etc/ambari-agent/conf/"
  exec_cmd all "sudo ambari-agent restart"
fi

