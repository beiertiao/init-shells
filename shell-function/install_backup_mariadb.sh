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

MASTER_IP="$1"
BIN_LOG="$2"
POSITION="$3"

function uninstall_mysql()
{
  sudo systemctl stop mysqld || echo skip stop mysqld
  sudo systemctl stop mariadb || echo skip stop mariadb
  sudo ps aux | grep mysqld | grep -v grep | awk '{print $2}' | xargs -i kill -9 {} || true

  sudo rpm -qa | grep mysql | xargs -i rpm -e {} --nodeps >/dev/null
  sudo rpm -qa | grep mysql-community | xargs -i rpm -e {} --nodeps >/dev/null
  sudo rpm -qa | grep mariadb | xargs -i rpm -e {} --nodeps >/dev/null

  sudo rm -rf /var/lib/mysql /usr/lib64/mysql /var/log/mysqld.log /etc/my.cnf /etc/my.cnf.d 
  sudo test -d /usr/local/mysql && sudo rm -rf /usr/local/mysql

  sudo rpm -qa|grep mariadb
  sudo rpm -qa|grep mysql
}

function change_mysql_conf()
{
  CNF_FILE="$1"
  sudo sed -i '/server-id.*/d' $CNF_FILE
  sudo sed -i '/log_bin.*/d' $CNF_FILE
  sudo sed -i '/expire_logs_days.*/d' $CNF_FILE
  sudo sed -i '/relay_log.*/d' $CNF_FILE
  sudo sed -i '/skip-slave-start.*/d' $CNF_FILE
  sudo sed -i '/binlog-format.*/d' $CNF_FILE
  sudo sed -i '/sync_binlog.*/d' $CNF_FILE
  sudo sed -i '/max_connections.*/d' $CNF_FILE
  sudo sed -i '/lower_case_table_names.*/d' $CNF_FILE
  sudo sed -i '/innodb_buffer_pool.*/d' $CNF_FILE
  sudo sed -i '/innodb_large_prefix.*/d' $CNF_FILE
  sudo sed -i '/innodb_file_.*/d' $CNF_FILE
  sudo sed -i '/skip-external-locking.*/d' $CNF_FILE

  sudo sed -i '/\[mysqld\]/askip-external-locking' $CNF_FILE
  sudo sed -i '/\[mysqld\]/ainnodb_file_per_table=on' $CNF_FILE
  K_10=$(sudo /usr/bin/uname -r | grep -c 'ky10' || true)
  if [ $K_10 -ne 1 ]; then
    sudo sed -i '/\[mysqld\]/ainnodb_file_format=Barracuda' $CNF_FILE
    sudo sed -i '/\[mysqld\]/ainnodb_large_prefix=on' $CNF_FILE
  fi
  sudo sed -i '/\[mysqld\]/ainnodb_buffer_pool_instances=8' $CNF_FILE
  sudo sed -i '/\[mysqld\]/ainnodb_buffer_pool_size=16G' $CNF_FILE
  sudo sed -i '/\[mysqld\]/alower_case_table_names=1' $CNF_FILE
  sudo sed -i '/\[mysqld\]/amax_connections=8192' $CNF_FILE
  sudo sed -i '/\[mysqld\]/async_binlog=1' $CNF_FILE
  sudo sed -i '/\[mysqld\]/abinlog-format=ROW' $CNF_FILE
  sudo sed -i '/\[mysqld\]/askip-slave-start' $CNF_FILE
  sudo sed -i '/\[mysqld\]/arelay_log-index=slave-relay-bin.index' $CNF_FILE
  sudo sed -i '/\[mysqld\]/arelay_log=slave-relay-bin' $CNF_FILE
  sudo sed -i '/\[mysqld\]/aexpire_logs_days=10' $CNF_FILE
  sudo sed -i '/\[mysqld\]/alog_bin=slave-bin' $CNF_FILE
  sudo sed -i '/\[mysqld\]/aserver-id=102' $CNF_FILE
}

set +e
uninstall_mysql
set -e

if [ 0 -eq $(sudo rpm -qa|grep -c mariadb-server) ]; then
  sudo yum -q -y install expect mariadb-server >/dev/null
  set -x
  mysql_pwd=""
  sudo systemctl start mariadb
  sudo systemctl enable mariadb
  sudo ${CURR_PATH}/mysql_setup.sh "$MYSQL_PASSWORD"
  sleep 3
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%'IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "flush privileges"

  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "set global max_connect_errors = 1000;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "flush hosts;"

  C_8=$(sudo /usr/bin/uname -r | grep -c 'cl8' || true)
  E_8=$(sudo /usr/bin/uname -r | grep -c 'el8' || true)
  C_7=$(sudo /usr/bin/uname -r | grep -c 'cl7' || true)
  E_7=$(sudo /usr/bin/uname -r | grep -c 'el7' || true)
  K_10=$(sudo /usr/bin/uname -r | grep -c 'ky10' || true)
  if [ $E_8 -eq 1 -o $C_8 -eq 1 -o $K_10 -eq 1 ]; then
    change_mysql_conf /etc/my.cnf.d/mariadb-server.cnf
  elif [ $E_7 -eq 1 -o $C_7 -eq 1 ]; then
    change_mysql_conf /etc/my.cnf.d/server.cnf
  else
    echo "Not support os!!!"
    exit 1
  fi

  #sudo systemctl restart mariadb.service
  sudo systemctl stop mariadb.service
  sudo netstat -nalp | grep 3306 |grep LISTEN | awk '{print $NF}' | awk -F '/' '{print $1}' | xargs -i kill -9 {} || echo port not exist
  sleep 5
  sudo systemctl start mariadb.service

  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "change master to master_host='$MASTER_IP', master_port=3306, master_user='root', master_password='$MYSQL_PASSWORD', master_log_file='$BIN_LOG', master_log_pos=$POSITION;"
  sleep 1
  sudo mysql -u root -p"$MYSQL_PASSWORD" -e "start slave;"
  sleep 10
  check_slave_status  
fi
