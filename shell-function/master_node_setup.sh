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

echo -e "############ master node settings #################\n"

# pre work: disable firewalld, optimized ssh config

systemctl stop firewalld || echo skip stop firewall
systemctl disable firewalld || echo skip disable firewall
setenforce 0 || echo skip setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
/sbin/iptables -P INPUT ACCEPT; /sbin/iptables -F
sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i -e "/GSSAPIAuthentication/d" /etc/ssh/sshd_config
grep "GSSAPIAuthentication no" /etc/ssh/sshd_config >/dev/null || echo -e "\nGSSAPIAuthentication no" >> /etc/ssh/sshd_config
# test yum
if [ x$ARCH = "xaarch64" ]; then
  test -f /usr/bin/yum || ln -sf /usr/bin/dnf-3 /usr/bin/yum
fi

yum install -y -q sshpass >/dev/null
