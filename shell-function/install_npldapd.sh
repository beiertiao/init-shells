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

function stop_npldapd()
{
  exec_cmd all "sudo systemctl stop nslcd || true"
}

function install_npldapd()
{
  E_C=$(sudo /usr/bin/uname -r | grep -c 'cl8' || true)
  if [ $E_C -ne 0 ]; then
    exec_cmd all "sudo yum install -y openldap-2.5-clients >/dev/null || true"
  else
    exec_cmd all "sudo yum install -y openldap-clients >/dev/null || true"
  fi 
  exec_cmd all "sudo yum install -y nss-pam-ldapd >/dev/null || true"
}

function config_npldapd()
{
  CACERT_DIR="/etc/openldap/cacertsorg"
  E_C=$(sudo /usr/bin/uname -r | grep -c 'cl8' || true)
  if [ $E_C -ne 0 ]; then
    CACERT_DIR="/usr/local/openldap/etc/openldap/cacertsorg"
  fi 
  exec_cmd all "sudo mkdir -p $CACERT_DIR || true"
  sudo cp ${CURR_PATH}/../config/openldap/nsswitch.conf /tmp/nsswitch.conf
  sudo cp ${CURR_PATH}/../config/openldap/nslcd.conf.tpl /tmp/nslcd.conf
  if [ $E_C -ne 0 ]; then
    sudo sed -i "s/OPENLDAP_SERVER/$MYSQL_VIP/g" /tmp/nslcd.conf
  else
    LOCAL_HOSTNAME=$(cat ${CURR_PATH}/../config/ip.txt | grep $LOCAL_IP | awk '{print $NF}')
    sudo sed -i "s/OPENLDAP_SERVER/$LOCAL_HOSTNAME/g" /tmp/nslcd.conf
  fi
  sudo sed -i "s#CACERT_ORG#$CACERT_DIR#g" /tmp/nslcd.conf
  sudo sed -i "s/PASSWORD/$KRB5_PASSWORD/g" /tmp/nslcd.conf
  DOMAIN=$(echo "$KRB5_REALMS" | sed 's/\..*//' | tr 'A-Z' 'a-z')
  sudo sed -i "s#my-domain#$DOMAIN#g" /tmp/nslcd.conf

  copy_file all "/tmp/nsswitch.conf" "/tmp/"
  copy_file all "/tmp/nslcd.conf" "/tmp/"
  exec_cmd all "sudo mv /tmp/nsswitch.conf /etc/"
  exec_cmd all "sudo mv /tmp/nslcd.conf /etc/"
  exec_cmd all "sudo chmod 600 /etc/nslcd.conf"
  exec_cmd all "sudo chmod 644 /etc/nsswitch.conf"
}
 
function start_npldapd()
{
  exec_cmd all "sudo systemctl enable nslcd"
  exec_cmd all "sudo systemctl start nslcd"
}

stop_npldapd
install_npldapd
config_npldapd
start_npldapd
