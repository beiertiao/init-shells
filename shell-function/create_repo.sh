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

echo -e "############ create local repo #################\n"

# pre work: disable firewalld, optimized ssh config

sudo systemctl stop firewalld || echo skip stop firewall
sudo systemctl disable firewalld || echo skip disable firewall
sudo setenforce 0 || echo skip setenforce 0
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
sudo /sbin/iptables -P INPUT ACCEPT; sudo /sbin/iptables -F
sudo sed -i 's/#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sudo sed -i -e "/GSSAPIAuthentication/d" /etc/ssh/sshd_config
sudo grep "GSSAPIAuthentication no" /etc/ssh/sshd_config >/dev/null || echo -e "\nGSSAPIAuthentication no" | sudo tee -a /etc/ssh/sshd_config
if [ x$ARCH = "xaarch64" ]; then
  sudo test -f /usr/bin/yum || sudo ln -sf /usr/bin/dnf-3 /usr/bin/yum
fi

sudo mkdir -p /etc/yum.repos.d/bak
if [ $(sudo find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" | wc -l) -ne 0 ]; then
  sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/
fi
sudo mkdir -p /etc/yum.repos.d/bak

sudo cp ${CURR_PATH}/../config/repo/local.repo /etc/yum.repos.d/
CENTOS_RPM_DIR=`eval "pushd . >/dev/null; cd ${CURR_PATH}/..; pwd; popd>/dev/null"`
sudo sed -i "s#LOCAL_INSTALL_DIR#$CENTOS_RPM_DIR#" /etc/yum.repos.d/local.repo

# makecache
sudo yum clean all >/dev/null && sudo yum makecache >/dev/null

sudo yum install -y -q httpd sshpass >/dev/null

sudo systemctl restart httpd
sudo systemctl enable httpd.service

# unarchive
sudo test -d ${DATA_ROOT_DIR}/$ARCH && sudo rm -rf ${DATA_ROOT_DIR}/$ARCH
sudo chmod -R 755 ${DATA_ROOT_DIR}
sudo mkdir ${DATA_ROOT_DIR}/$ARCH
sudo cp -rf ${CURR_PATH}/../$ARCH ${DATA_ROOT_DIR}/
sudo chmod 755 ${DATA_ROOT_DIR}/$ARCH -R

sudo mkdir -p /etc/yum.repos.d/bak
if [ $(sudo find /etc/yum.repos.d/ -maxdepth 1 -name "*.repo" | wc -l) -ne 0 ]; then
  sudo mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/
fi
# make file yum repo
sudo cp ${CURR_PATH}/../config/repo/cestc.repo /etc/yum.repos.d/
sudo sed -i "s/YUM_HOSTNAME/$LOCAL_IP/g" /etc/yum.repos.d/cestc.repo

# config hosts
#YUM_REPO_IP=$(sudo hostname --all-ip-addresses | awk '{print $1}')
#if [ $(grep -c $YUM_HOSTNAME /etc/hosts) -eq 0 ]; then
#  echo "$YUM_REPO_IP $YUM_HOSTNAME" | sudo tee -a /etc/hosts
#fi

# httpd dir
sudo /usr/bin/mkdir -p /tmp/$ARCH
sudo test -d /var/www/html/$ARCH || sudo /usr/bin/ln -sf ${DATA_ROOT_DIR}/$ARCH /var/www/html/$ARCH
sudo chmod 755 /var/www/html/ -R

# makecache
sudo yum clean all >/dev/null && sudo yum makecache >/dev/null
