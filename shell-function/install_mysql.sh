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

function install_gravitino_mysql_client()
{
  exec_cmd all "sudo yum install -y mariadb >/dev/null || true"
}

function init_db()
{
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE ranger character set utf8"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER 'rangeradmin'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON ranger.* to 'rangeradmin'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON ranger.* to 'rangeradmin'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE hive character set utf8"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER 'hive'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON hive.* to 'hive'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON hive.* to 'hive'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE ambari character set utf8"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER 'ambari'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON ambari.* to 'ambari'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON ambari.* to 'ambari'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE DATABASE gravitino character set utf8"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "CREATE USER 'gravitino'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON gravitino.* to 'gravitino'@'%' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL ON gravitino.* to 'gravitino'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD'"
  sudo mysql -u root -p${MYSQL_PASSWORD} -NBe "FLUSH PRIVILEGES"
  sudo mysql -u root -p${MYSQL_PASSWORD} -NBe "use ambari; source ${CURR_PATH}/../config/Ambari-DDL-MySQL-CREATE.sql;"
  # change ambari default password (Cestc_01)
  sudo mysql -u root -p${MYSQL_PASSWORD} -NBe "use ambari; update user_authentication set authentication_key = 'ebc185d9956201d31ec2b5c8edac9de880d7124d3fa0785c78199a2b5c92730e0aab4027649ef316' where user_id in (select user_id from users where user_name = 'admin');"
}

function change_master_for_slave()
{
  SLAVE_IP="$1"
  POSITION=`sudo mysql -uroot -p"$MYSQL_PASSWORD" -h$SLAVE_IP -e "show master status\G" | grep Position | awk '{print $NF}'`
  BIN_LOG=`sudo mysql -uroot -p"$MYSQL_PASSWORD" -h$SLAVE_IP -e "show master status\G" | grep File | awk '{print $NF}'`
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "change master to master_host='$SLAVE_IP', master_port=3306, master_user='root', master_password='$MYSQL_PASSWORD', master_log_file='$BIN_LOG', master_log_pos=$POSITION;"
  sleep 1
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "start slave;"
  sleep 1
}

function import_mysql_tzinfo()
{
  sudo mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -uroot mysql -p${MYSQL_PASSWORD}
}

${bin}/install_master_mariadb.sh

scp -P ${SSH_PORT} -r ${bin}/../shell-function/cie_config.sh ${bin}/../shell-function/mysql_setup.sh ${bin}/../shell-function/install_backup_mariadb.sh $USER@${SLAVE_MYSQL_IP}:/tmp/
POSITION=`sudo mysql -uroot -p"$MYSQL_PASSWORD" -e "show master status\G" | grep Position | awk '{print $NF}'`
BIN_LOG=`sudo mysql -uroot -p"$MYSQL_PASSWORD" -e "show master status\G" | grep File | awk '{print $NF}'`
ssh -l $USER -p ${SSH_PORT} $SLAVE_MYSQL_IP "sudo sh /tmp/install_backup_mariadb.sh $LOCAL_IP $BIN_LOG $POSITION"
scp -P ${SSH_PORT} -r $USER@$SLAVE_MYSQL_IP:/tmp/slave_status /tmp

if [ x`cat /tmp/slave_status` = 'x0' ]; then
  # for mysql ha
  change_master_for_slave "$SLAVE_MYSQL_IP"
  check_slave_status
  install_keepalived $MASTER_MYSQL_IP $SLAVE_MYSQL_IP
  config_mysql_keepalived $MASTER_MYSQL_IP $SLAVE_MYSQL_IP
  restart_keepalived $MASTER_MYSQL_IP $SLAVE_MYSQL_IP
  install_gravitino_mysql_client
  if [ x`cat /tmp/slave_status` = 'x0' ]; then
    init_db
    config_mysql_status $MASTER_MYSQL_IP $SLAVE_MYSQL_IP
    import_mysql_tzinfo
  else
    echo "master status check error"
    exit 1
  fi
else
  echo "slave status check error"
  exit 1
fi
