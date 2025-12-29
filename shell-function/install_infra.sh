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

echo -e "############ install infra ###################\n"

function install_base_packages()
{
  copy_file all "/etc/hosts" "/tmp/"
  exec_cmd all "sudo mv /tmp/hosts /etc/"
  exec_cmd all "sudo rm -rf /tmp/yum.repos.d || true"
  copy_file all "/etc/yum.repos.d" "/tmp/"
  exec_cmd all "sudo rm -rf /etc/yum.repos.d"
  exec_cmd all "sudo mv /tmp/yum.repos.d /etc/"
  if [ x"$ADD_NEW_HOST" != x"1" ]; then
    sudo cp /etc/ssh/sshd_config /tmp
    sudo chown $USER:$USER /tmp/sshd_config
  else
    sudo cp -f /etc/ssh/sshd_config /tmp
    sudo chown $USER:$USER /tmp/sshd_config
  fi
  copy_file all "/tmp/sshd_config" "/tmp/"
  exec_cmd all "sudo mv /tmp/sshd_config /etc/ssh/"
  exec_cmd all "sudo chmod 600 /etc/ssh/sshd_config"
  exec_cmd all "sudo chown root:root /etc/ssh/sshd_config"
  exec_cmd all "sudo systemctl restart sshd >/dev/null"  
  exec_cmd all "sudo yum install -y vim unzip net-tools lsof python2 python2-devel >/dev/null"
  exec_cmd all "sudo test -f /usr/bin/python || sudo ln -sf /usr/bin/python2 /usr/bin/python"
}

function downgrade_glibc_langpack_en
{
  exec_cmd all "sudo yum downgrade -y glibc-langpack-en-2.28-151.el8 >/dev/null"
}

function time_sync_cclinux()
{
  ## set timezone
  exec_cmd all "sudo cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime || true"

  exec_cmd all "sudo yum install -y rsync chrony >/dev/null"
  exec_cmd all "sudo systemctl enable chronyd >/dev/null"
  ## for server
  if [ x"$ADD_NEW_HOST" != x"1" ]; then
    sudo cp ${CURR_PATH}/../config/chrony.conf.tpl /tmp/chrony.conf
    sudo sed -i "s/MASTER_IP/$LOCAL_IP/g" /tmp/chrony.conf
    sudo sed -i '/^server.*$/d' /tmp/chrony.conf
    echo "local stratum 10" | sudo tee -a /tmp/chrony.conf
    sudo mv /tmp/chrony.conf /etc/
  fi
  ## for clients
  sudo cp ${CURR_PATH}/../config/chrony.conf.tpl /tmp/chrony.conf
  sudo sed -i "s/MASTER_IP/$LOCAL_IP/g" /tmp/chrony.conf
  sudo sed -i '/^.*allow.*$/d' /tmp/chrony.conf
  copy_file client "/tmp/chrony.conf" "/tmp/"
  exec_cmd client "sudo mv /tmp/chrony.conf /etc/"
  exec_cmd all "sudo systemctl restart chronyd >/dev/null"
  exec_cmd all "sudo chronyc -a makestep >/dev/null"
  exec_cmd client "sudo chronyc sources -v >/dev/null"
}

function set_hostname()
{
  HOSTS=`cat ${HOST_FILE} | awk '{print $1}'`
  for H in $HOSTS
  do
     line=`grep "$H[[:space:]]" ${HOST_FILE}`
     hostsname=`echo "$line" | awk '{print $NF}'`
     ssh -p ${SSH_PORT} $USER@$H "sudo hostnamectl set-hostname '$hostsname'"
     ssh -p ${SSH_PORT} $USER@$H "echo '$hostsname' | sudo tee /etc/sysconfig/network"
     ssh -p ${SSH_PORT} $USER@$H "sudo sed -i '/.*127.0.0.1.*/d' /etc/hosts || true"
     ssh -p ${SSH_PORT} $USER@$H "sudo sed -i '/.*localhost.*/d' /etc/hosts || true"
     if [ $(sudo grep -c "$hostsname" /etc/hosts) -eq 0 ]; then
       echo -e "$H\t$hostsname" | sudo tee -a /etc/hosts
     fi
  done
  copy_file all "/etc/hosts" "/tmp/"
  exec_cmd all "sudo mv /tmp/hosts /etc/"
}

function close_firewall()
{
  exec_cmd all "sudo systemctl stop firewalld.service || echo 'skip'"
  exec_cmd all "sudo systemctl disable firewalld.service || echo 'skip'"
}

function set_swappiness()  
{
  exec_cmd all "sudo sed -i '/vm.swappiness=/d' /etc/sysctl.conf"
  exec_cmd all "echo 'vm.swappiness=1' | sudo tee -a /etc/sysctl.conf"
  exec_cmd all "sudo sysctl -p || true"
}

function disable_ipv6()
{
  exec_cmd all "sudo sed -i '/net.ipv6.conf.all.disable_ipv6=/d' /etc/sysctl.conf"
  exec_cmd all "echo 'net.ipv6.conf.all.disable_ipv6=1' | sudo tee -a /etc/sysctl.conf"
  exec_cmd all "sudo sysctl -p || true"
}

function set_hugepage() 
{
  exec_cmd all "echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag"
  exec_cmd all "echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"
  exec_cmd all "sudo sed -i '/transparent_hugepage/d' /etc/rc.d/rc.local"
  exec_cmd all "echo 'test -f /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.d/rc.local"
  exec_cmd all "echo 'test -f /sys/kernel/mm/transparent_hugepage/defrag && echo never > /sys/kernel/mm/transparent_hugepage/defrag' | sudo tee -a /etc/rc.d/rc.local"
}

function set_selinux()
{
  exec_cmd all "sudo setenforce 0 || echo 'skip'"
  exec_cmd all "sudo sed -i 's#SELINUX=enforcing#SELINUX=disabled#' /etc/selinux/config || echo 'skip'"
}

function set_redhat_version()
{
  #exec_cmd all "grep '${YUM_HOSTNAME}' /etc/hosts || echo '${LOCAL_IP} ${YUM_HOSTNAME}' | sudo tee -a /etc/hosts"
  E_C=$(sudo /usr/bin/uname -r | grep -c 'cl8' || true)
  E_K=$(sudo /usr/bin/uname -r | grep -c 'ky10' || true)
  E_O=$(sudo /usr/bin/uname -r | grep -c 'oe1' || true)
  if [ $E_C -ne 0 ]; then
    exec_cmd all "echo 'CentOS linux release 8.2' | sudo tee /etc/redhat-release"
  fi
  if [ $E_K -ne 0 ]; then
    exec_cmd all "echo 'CentOS linux release 8.2' | sudo tee /etc/kylin-release"
  fi
  if [ $E_O -ne 0 ]; then
    exec_cmd all "echo 'CentOS linux release 8.2' | sudo tee /etc/openEuler-release"
  fi
}

set_hostname
install_base_packages
time_sync_cclinux
close_firewall
set_swappiness
disable_ipv6
set_hugepage
set_selinux
set_redhat_version
