#!/bin/bash
set -ex

CURR_PATH=$(sudo readlink -f "$(dirname "$0")")

this="${BASH_SOURCE-$0}"
bin=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
if [[ -f "${bin}/cie_config.sh" ]]; then
  . ${bin}/cie_config.sh
else
  echo "ERROR: Cannot execute ${bin}/cie_config.sh." 2>&1
  exit 1
fi

echo -e "############ add new hosts ###################\n"

echo -e "############ step-0: ssh without passwd ################\n" >> /tmp/.add-new-hosts-log
sh $CURR_PATH/newhosts_without_passwd.sh >> /tmp/.add-new-hosts-log 2>&1
echo ""


## install infra for new hosts
echo -e "############ step-1: install infra #################\n" > /tmp/.add-new-hosts-log
sh ${CURR_PATH}/install_infra.sh >> /tmp/.add-new-hosts-log
echo ""

## install jdk for new hosts
echo -e "############ step-2: install jdk ###################\n" >> /tmp/.add-new-hosts-log
sh ${CURR_PATH}/install_jdk.sh >> /tmp/.add-new-hosts-log
echo ""

## install ambari agent for new hosts
echo -e "############ step-3: install cie agent #############\n" >> /tmp/.add-new-hosts-log
sh ${CURR_PATH}/install_cie_agent.sh >> /tmp/.add-new-hosts-log
echo ""

## install kerberos client for new hosts
echo -e "############ step-4: install kerberos agent ########\n" >> /tmp/.add-new-hosts-log
sh ${CURR_PATH}/install_kerberos_client.sh >> /tmp/.add-new-hosts-log
echo ""

export HOST_FILE=${CURR_PATH}/../config/ip.txt
copy_file all "/etc/hosts" "/tmp/" >> /tmp/.add-new-hosts-log
exec_cmd all "sudo mv /tmp/hosts /etc/" >> /tmp/.add-new-hosts-log

#touch $CURR_PATH/../add-new-hosts-install.txt >> /tmp/.add-new-hosts-log 2>&1

