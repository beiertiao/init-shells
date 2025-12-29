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

echo -e "############ install cie ###################\n"

function install_config_master_ambari_server()
{
  ### stop ambari-server and remove
  sudo systemctl stop ambari-server || true
  sudo yum remove -y ambari-server >/dev/null || true
  sudo yum install -y expect > /dev/null

  sudo yum install -y ambari-server > /dev/null
  grep "api.csrfPrevention.enabled" /etc/ambari-server/conf/ambari.properties -c >/dev/null || echo "api.csrfPrevention.enabled=false" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  grep "server.startup.web.timeout" /etc/ambari-server/conf/ambari.properties -c >/dev/null || echo "server.startup.web.timeout=180" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  sudo sed -i '/server.jdbc.driver.path/d' /etc/ambari-server/conf/ambari.properties
  echo "server.jdbc.driver.path=/usr/share/java/mysql-connector-java.jar" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  sudo sed -i '/client.api.port/d' /etc/ambari-server/conf/ambari.properties
  echo "client.api.port=$AMBARI_SERVER_PORT" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  sudo sed -i '/security.server.one_way_ssl.port/d' /etc/ambari-server/conf/ambari.properties
  echo "security.server.one_way_ssl.port=8442" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  sudo sed -i '/security.server.two_way_ssl.port/d' /etc/ambari-server/conf/ambari.properties
  echo "security.server.two_way_ssl.port=8443" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  echo "license.host=$LICENSE_HOST" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  echo "license.product.code=$LICENSE_PRODUCT_CODE" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  echo "license.free.days=$LICENSE_FREE_DAYS" | sudo tee -a /etc/ambari-server/conf/ambari.properties
  echo "license.warn.days=$LICENSE_WARN_DAYS" | sudo tee -a /etc/ambari-server/conf/ambari.properties

  sudo ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

  E_K=$(sudo /usr/bin/uname -r | grep -c 'ky10' || true)
  if [ $E_K -eq 1 ]; then
    sed -i "79a _IS_KYLIN_LINUX = os.path.exists('/etc/kylin-release')" /usr/lib/ambari-server/lib/ambari_commons/os_check.py
    sed -i '88a def _is_kylin_linux():' /usr/lib/ambari-server/lib/ambari_commons/os_check.py
    sed -i '89a \  return _IS_KYLIN_LINUX' /usr/lib/ambari-server/lib/ambari_commons/os_check.py
    sed -i '206a \      elif _is_kylin_linux():' /usr/lib/ambari-server/lib/ambari_commons/os_check.py
    sed -i '207a \        distribution = ("centos", "8", "core")' /usr/lib/ambari-server/lib/ambari_commons/os_check.py
  fi

  source /etc/profile >/dev/null 2>&1
  JAVAHOME=`env | grep JAVA_HOME | awk -F '=' '{print $NF}'`
  HOSTNAME=`grep $LOCAL_IP[[:space:]] ${HOST_FILE} | awk '{print $NF}'`
  if [ ! -z $MYSQL_VIP ]; then
    HOSTNAME="$MYSQL_VIP"
  fi

  sudo ${CURR_PATH}/cie_setup.sh "$JAVAHOME" "$HOSTNAME" "$MYSQL_PASSWORD"
  sleep 3
}

function start_master_ambari_server()
{
  sudo ambari-server start
  sleep 3
  touch /etc/keepalived/.some_one_as_live
}

function install_config_start_ambari_agent() 
{
  exec_cmd all "sudo systemctl stop ambari-agent || true"
  exec_cmd all "sudo yum remove -y ambari-agent >/dev/null || true"
  exec_cmd all "sudo yum install -y ambari-agent > /dev/null"
  HOSTNAME=`grep $LOCAL_IP[[:space:]] ${HOST_FILE} | awk '{print $NF}'`
  if [ ! -z $MYSQL_VIP ]; then
    HOSTNAME="$MYSQL_VIP"
  fi
  exec_cmd all "sudo sed -i 's/^hostname=.*$/hostname=$HOSTNAME/g' /etc/ambari-agent/conf/ambari-agent.ini"
  copy_file all "${CURR_PATH}/../config/public_hostname.sh" "/tmp/"
  exec_cmd all "sudo mv /tmp/public_hostname.sh /var/lib/ambari-agent/"
  exec_cmd all "sudo sed -i '/hostname_script/d' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/system_resource_overrides=\/etc\/resource_overrides/a public_hostname_script=\/var\/lib\/ambari-agent\/public_hostname.sh' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/system_resource_overrides=\/etc\/resource_overrides/a hostname_script=\/var\/lib\/ambari-agent\/public_hostname.sh' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/url_port/d' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/\[server\]/aurl_port=8442' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/secured_url_port/d' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo sed -i '/\[server\]/asecured_url_port=8443' /etc/ambari-agent/conf/ambari-agent.ini"
  exec_cmd all "sudo ambari-agent restart"
}

function install_config_slave_ambari_server()
{
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo systemctl stop ambari-server || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo yum remove -y ambari-server >/dev/null || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo yum install -y ambari-server > /dev/null"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "grep 'api.csrfPrevention.enabled' /etc/ambari-server/conf/ambari.properties -c >/dev/null || echo 'api.csrfPrevention.enabled=false' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo sed -i '/server.jdbc.driver.path/d' /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'server.jdbc.driver.path=/usr/share/java/mysql-connector-java.jar' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo sed -i '/client.api.port/d' /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'client.api.port=$AMBARI_SERVER_PORT' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo sed -i '/security.server.one_way_ssl.port/d' /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'security.server.one_way_ssl.port=8442' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo sed -i '/security.server.two_way_ssl.port/d' /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'security.server.two_way_ssl.port=8443' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'license.host=$LICENSE_HOST' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'license.product.code=$LICENSE_PRODUCT_CODE' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'license.free.days=$LICENSE_FREE_DAYS' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "echo 'license.warn.days=$LICENSE_WARN_DAYS' | sudo tee -a /etc/ambari-server/conf/ambari.properties"
  sleep 3

  sudo scp -P ${SSH_PORT} -r /etc/ambari-server/conf/password.dat /etc/ambari-server/conf/ambari.properties $USER@$SLAVE_AMBARI_SERVER_IP:/etc/ambari-server/conf/
  sudo scp -P ${SSH_PORT} -r /var/lib/ambari-server/resources/mysql-connector-java.jar $USER@$SLAVE_AMBARI_SERVER_IP:/var/lib/ambari-server/resources/
  ssh -l $USER -p ${SSH_PORT} $SLAVE_AMBARI_SERVER_IP "sudo ln -sf /var/lib/ambari-server/resources/mysql-connector-java.jar /var/lib/ambari-server/resources/mysql-jdbc-driver.jar"
}

function config_ambari_server_ha() 
{
  config_ambari_server_keepalived $MASTER_AMBARI_SERVER_IP $SLAVE_AMBARI_SERVER_IP
  restart_keepalived $MASTER_AMBARI_SERVER_IP $SLAVE_AMBARI_SERVER_IP
}

clean_ambari_server_keepalived $MASTER_AMBARI_SERVER_IP $SLAVE_AMBARI_SERVER_IP
install_config_master_ambari_server
start_master_ambari_server
install_config_start_ambari_agent
install_config_slave_ambari_server
config_ambari_server_ha
