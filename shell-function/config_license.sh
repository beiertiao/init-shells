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

# 安装license
mkdir -p /home/cnbh
CURR_PATH=$(readlink -f "$(dirname "$0")")
tar -zxvf  $CURR_PATH/../license/license.tar.gz -C /home/cnbh
cp $CURR_PATH/../license/license.service /etc/systemd/system/license.service
chmod +x /home/cnbh/license/license
systemctl daemon-reload
systemctl enable license.service
systemctl start license.service

#往 slave 节点配置 license
ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "mkdir -p /home/cnbh"
# 复制 license 到 slave 节点
scp -P ${SSH_PORT} $CURR_PATH/../license/license.tar.gz $USER@$SLAVE_AMBARI_SERVER_IP:/home/cnbh
scp -P ${SSH_PORT} $CURR_PATH/../license/license.service $USER@$SLAVE_AMBARI_SERVER_IP:/home/cnbh

# 解压 license 到 slave 节点
ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "tar -zxvf  /home/cnbh/license.tar.gz -C /home/cnbh"

#仅配置 slave 节点的 license.service不需要启动
ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "cp /home/cnbh/license.service /etc/systemd/system/license.service"
ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "chmod +x /home/cnbh/license/license"
ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "systemctl daemon-reload"
