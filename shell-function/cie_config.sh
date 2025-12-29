#!/usr/bin/bash

CURR_PATH=$(sudo readlink -f "$(dirname "$0")")

export USER="root"
export SSH_PORT=22
export DATA_ROOT_DIR=/home
export MYSQL_PASSWORD='Cestc_01'
export MYSQL_VIP="10.253.128.248"
export AMBARI_SERVER_VIP=$MYSQL_VIP
export ENABLE_KERBEROS=0 ## 0 disable, 1 enable (ENABLE_KERBEROS or ENABLE_KERBEROS_LDAP choose one only)
export ENABLE_KERBEROS_LDAP=1 ## 0 disable, 1 enable (ENABLE_KERBEROS or ENABLE_KERBEROS_LDAP choose one only)
export KRB5_REALMS="CESTC.COM"
export KRB5_PASSWORD="$MYSQL_PASSWORD"
export OPENLDAP_PASSWORD="$MYSQL_PASSWORD"
export AMBARI_SERVER_PORT=8080
export AMBARI_SERVER_USERNAME="admin"
export AMBARI_SERVER_PASSWORD=$MYSQL_PASSWORD

export ARCH=`sudo arch`
export RAW_HOST_FILE=${CURR_PATH}/../config/ip.txt
export HOST_FILE=$RAW_HOST_FILE
export IP_REGEX="^(2[0-4][0-9]|25[0-5]|1[0-9][0-9]|[1-9]?[0-9])(\.(2[0-4][0-9]|25[0-5]|1[0-9][0-9]|[1-9]?[0-9])){3}$"
export NET_DEV=`sudo ip route get 1.1.1.1 | grep dev | awk '{print $5}'`
export LOCAL_IP=`sudo ip a | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | head -n1`
export LOCAL_HOSTNAME=$(sudo hostname -f)

export MASTER_MYSQL_IP="$LOCAL_IP"
export SLAVE_MYSQL_IP=$(cat ${HOST_FILE} | grep -v "$LOCAL_IP[[:space:]]" | head -n1 | awk '{print $1}')
export MASTER_AMBARI_SERVER_IP="$MASTER_MYSQL_IP"
export SLAVE_AMBARI_SERVER_IP="$SLAVE_MYSQL_IP"
export MASTER_OPENLDAP_IP="$MASTER_MYSQL_IP"
export SLAVE_OPENLDAP_IP="$SLAVE_MYSQL_IP"
export MASTER_KADMIN_SERVER_IP="$MASTER_MYSQL_IP"
export SLAVE_KADMIN_SERVER_IP="$SLAVE_MYSQL_IP"

export ADD_NEW_HOST=AD_NEW_HOSTS

### change for config dmp
export COORDINATOR_HOSTNAME="ky1"
export METASTORE_HOSTNAME="ky2"
export TRINO_KRB5_PASSWORD="$MYSQL_PASSWORD"
export LDAP_PASSWORD="$MYSQL_PASSWORD"
export DMP_USERS=("hive_cestc")
export DMP_USER_DEFAULT_PWD="123456"

export LICENSE_HOST="https://${MASTER_AMBARI_SERVER_IP}:9999"
export LICENSE_PRODUCT_CODE="CESTC012023090139912" #License 的产品码
export LICENSE_FREE_DAYS="180" #License 免费天数
export LICENSE_WARN_DAYS="30" #License 警告天数

### add new host
if [ x"$ADD_NEW_HOST" = x"1" ]; then
  HOST_FILE=${CURR_PATH}/../config/new_hosts
fi
###

### local ip prefer from host file
function relocate_local_ip()
{
  ALL_LOCAL_IPS=$(sudo ip a | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
  for IP in ${ALL_LOCAL_IPS[@]}
  do
    E=$(grep -c $IP $RAW_HOST_FILE || true)
    if [ $E -ne 0 ]; then
      LOCAL_IP=$IP
      break
    fi
  done
}

relocate_local_ip

function copy_file()
{
  all="$1"
  src="$2"
  dest="$3"

  if [ x"$all" = x"all" ]; then
    cat ${HOST_FILE} | awk '{print $1}' | xargs -i scp -P ${SSH_PORT} -r "$src" $USER@{}:"$dest"
  else
    cat ${HOST_FILE} | grep -v "$LOCAL_IP[[:space:]]" | awk '{print $1}' | xargs -i scp -P ${SSH_PORT} -r "$src" $USER@{}:"$dest"
  fi
}

function exec_cmd()
{
  all="$1"
  cmd="$2"

  if [ x"$all" = x"all" ]; then
    cat ${HOST_FILE} | awk '{print $1}' | xargs -i ssh -l $USER -p ${SSH_PORT} {} "$cmd"
  elif [ x"$all" = x"master" ]; then
    cat ${HOST_FILE} | grep "$LOCAL_IP[[:space:]]" | awk '{print $1}' | head -n1 | xargs -i ssh -l $USER -p ${SSH_PORT} {} "$cmd"
  else
    cat ${HOST_FILE} | grep -v "$LOCAL_IP[[:space:]]" | awk '{print $1}' | xargs -i ssh -l $USER -p ${SSH_PORT} {} "$cmd"
  fi
}

function check_slave_status()
{
  STATUS=`sudo mysql -u root -p"$MYSQL_PASSWORD" -e "show slave status\G"`
  IO_RUNNING_STATUS=`echo "$STATUS" | grep -c 'Slave_IO_Running: Yes'`
  SQL_RUNNING_STATUS=`echo "$STATUS" | grep -c 'Slave_SQL_Running: Yes'`
  BEHIND_STATUS=`echo "$STATUS" | grep -c 'Seconds_Behind_Master: 0'`
  if [ $IO_RUNNING_STATUS -eq 1 -a $SQL_RUNNING_STATUS -eq 1 -a $BEHIND_STATUS -eq 1 ]; then
    echo "slave status check ok!"
    echo "0" > /tmp/slave_status
  else
    echo "slave status check error: IO_RUNNING_STATUS:" $IO_RUNNING_STATUS ", SQL_RUNNING_STATUS:" $SQL_RUNNING_STATUS ", BEHIND_STATUS:" $BEHIND_STATUS
    echo "1" > /tmp/slave_status
    exit -1
  fi
}

function install_keepalived() 
{
  MASTER_IP="$1"
  SLAVE_IP="$2"

  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo yum remove -y keepalived"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo yum remove -y keepalived"
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo yum install -y keepalived"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo yum install -y keepalived"
}

function config_mysql_keepalived()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"

  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/mysql.sh $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/mysql.sh $USER@${SLAVE_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/keepalived.service $USER@${MASTER_IP}:/usr/lib/systemd/system/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/keepalived.service $USER@${SLAVE_IP}:/usr/lib/systemd/system/
  sudo cp ${bin}/../config/keepalived/keepalived.conf.tpl /tmp/keepalived.conf
  sudo scp -P ${SSH_PORT} -r /tmp/keepalived.conf $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r /tmp/keepalived.conf $USER@${SLAVE_IP}:/etc/keepalived/

  sudo cp ${bin}/../config/keepalived/master_mysql_k.conf /tmp/
  sudo sed -i "s/MYSQL_VIP/$MYSQL_VIP/g" /tmp/master_mysql_k.conf
  sudo sed -i "s/MASTER_IP/$MASTER_IP/g" /tmp/master_mysql_k.conf
  sudo sed -i "s/NET_DEV/$NET_DEV/g" /tmp/master_mysql_k.conf
  sudo scp -P ${SSH_PORT} -r /tmp/master_mysql_k.conf $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../shell-function/config_keepalive.sh $USER@${MASTER_IP}:/tmp/
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo /tmp/config_keepalive.sh master_mysql_k.conf"

  sudo cp ${bin}/../config/keepalived/slave_mysql_k.conf /tmp/
  sudo sed -i "s/MYSQL_VIP/$MYSQL_VIP/g" /tmp/slave_mysql_k.conf
  sudo sed -i "s/SLAVE_IP/$SLAVE_IP/g" /tmp/slave_mysql_k.conf
  sudo sed -i "s/NET_DEV/$NET_DEV/g" /tmp/slave_mysql_k.conf
  sudo scp -P ${SSH_PORT} -r /tmp/slave_mysql_k.conf $USER@${SLAVE_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../shell-function/config_keepalive.sh $USER@${SLAVE_IP}:/tmp/
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo /tmp/config_keepalive.sh slave_mysql_k.conf"
}

function clean_ambari_server_keepalived()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo sed -i '/.*master_ambari_server_k.conf.*/d' /etc/keepalived/keepalived.conf"
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -f /etc/keepalived/.some_one_as_live || true"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo sed -i '/.*slave_ambari_server_k.conf.*/d' /etc/keepalived/keepalived.conf"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -f /etc/keepalived/.some_one_as_live || true"
  restart_keepalived $MASTER_IP $SLAVE_IP
}

function config_ambari_server_keepalived()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"

  sudo cp ${bin}/../config/keepalived/ambari-server.sh /tmp/
  sudo sed -i "s/AMBARI_SERVER_PORT/$AMBARI_SERVER_PORT/g" /tmp/ambari-server.sh
  sudo cp ${bin}/../config/keepalived/config_ambari.sh ${bin}/../config/keepalived/config_kerberos.sh /tmp
  sudo sed -i "s/AMBARI_PWD/$AMBARI_SERVER_PASSWORD/g" /tmp/config_ambari.sh
  sudo sed -i "s/AMBARI_PORT/$AMBARI_SERVER_PORT/g" /tmp/config_ambari.sh
  sudo sed -i "s/AMBARI_VIP/$AMBARI_SERVER_VIP/g" /tmp/config_ambari.sh
  sudo sed -i "s/AMBARI_VIP/$AMBARI_SERVER_VIP/g" /tmp/config_kerberos.sh
  sudo scp -P ${SSH_PORT} -r /tmp/ambari-server.sh /tmp/config_ambari.sh /tmp/config_kerberos.sh $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r /tmp/ambari-server.sh /tmp/config_ambari.sh /tmp/config_kerberos.sh $USER@${SLAVE_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/ambari-check ${bin}/../config/keepalived/keepalived-check ${bin}/../config/keepalived/kerberos-check $USER@${MASTER_IP}:/etc/cron.d/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/keepalived/ambari-check ${bin}/../config/keepalived/keepalived-check ${bin}/../config/keepalived/kerberos-check $USER@${SLAVE_IP}:/etc/cron.d/
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo chmod 644 /etc/cron.d/ambari-check /etc/cron.d/keepalived-check /etc/cron.d/kerberos-check"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo chmod 644 /etc/cron.d/ambari-check /etc/cron.d/keepalived-check /etc/cron.d/kerberos-check"

  sudo cp ${bin}/../config/keepalived/master_ambari_server_k.conf /tmp/
  sudo sed -i "s/AMBARI_SERVER_VIP/$AMBARI_SERVER_VIP/g" /tmp/master_ambari_server_k.conf
  sudo sed -i "s/MASTER_IP/$MASTER_IP/g" /tmp/master_ambari_server_k.conf
  sudo sed -i "s/NET_DEV/$NET_DEV/g" /tmp/master_ambari_server_k.conf
  sudo scp -P ${SSH_PORT} -r /tmp/master_ambari_server_k.conf $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../shell-function/config_keepalive.sh $USER@${MASTER_IP}:/tmp/
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo /tmp/config_keepalive.sh master_ambari_server_k.conf"

  sudo cp ${bin}/../config/keepalived/slave_ambari_server_k.conf /tmp/
  sudo sed -i "s/AMBARI_SERVER_VIP/$AMBARI_SERVER_VIP/g" /tmp/slave_ambari_server_k.conf
  sudo sed -i "s/SLAVE_IP/$SLAVE_IP/g" /tmp/slave_ambari_server_k.conf
  sudo sed -i "s/NET_DEV/$NET_DEV/g" /tmp/slave_ambari_server_k.conf
  sudo scp -P ${SSH_PORT} -r /tmp/slave_ambari_server_k.conf $USER@${SLAVE_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../shell-function/config_keepalive.sh $USER@${SLAVE_IP}:/tmp/
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo /tmp/config_keepalive.sh slave_ambari_server_k.conf"
}

function restart_keepalived()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"

  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo chmod 644 /etc/keepalived/*.conf"
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo systemctl enable keepalived; sudo systemctl restart keepalived; sudo systemctl status keepalived"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo chmod 644 /etc/keepalived/*.conf"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo systemctl enable keepalived; sudo systemctl restart keepalived; sudo systemctl status keepalived"
}

function config_mysql_status()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"

  sudo cp ${bin}/../config/mysql/config_mysql.sh /tmp
  sudo sed -i "s/MYSQL_PWD/$MYSQL_PASSWORD/g" /tmp/config_mysql.sh
  sudo scp -P ${SSH_PORT} -r /tmp/config_mysql.sh $USER@${MASTER_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r /tmp/config_mysql.sh $USER@${SLAVE_IP}:/etc/keepalived/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/mysql/mysql-check $USER@${MASTER_IP}:/etc/cron.d/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config/mysql/mysql-check $USER@${SLAVE_IP}:/etc/cron.d/
  sudo ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo chmod 644 /etc/cron.d/mysql-check"
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo chmod 644 /etc/cron.d/mysql-check"
}
