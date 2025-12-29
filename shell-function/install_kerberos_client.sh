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

function install_krb5_client()
{
  exec_cmd client "sudo yum remove -y krb5-workstation >/dev/null || true"
  exec_cmd client "sudo yum install -y krb5-libs krb5-workstation >/dev/null"
}

function config_krb5_client()
{
  sudo cp -f /etc/krb5.conf /tmp
  copy_file all "/tmp/krb5.conf" "/tmp/"
  exec_cmd all "sudo mv /tmp/krb5.conf /etc/"
  exec_cmd all "sudo chmod 644 /etc/krb5.conf"
}

if [ x"$ENABLE_KERBEROS_LDAP" = x"1" -o x"$ENABLE_KERBEROS" = x"1" ]; then
  install_krb5_client
  config_krb5_client
fi

