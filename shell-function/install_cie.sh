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
### stop ambari-server and remove
sudo systemctl stop ambari-server || true
sudo yum remove -y ambari-server >/dev/null || true

sudo yum install -y expect > /dev/null

sudo yum install -y ambari-server > /dev/null
grep "api.csrfPrevention.enabled" /etc/ambari-server/conf/ambari.properties -c >/dev/null || echo "api.csrfPrevention.enabled=false" | sudo tee -a /etc/ambari-server/conf/ambari.properties
sudo sed -i '/server.jdbc.driver.path/d' /etc/ambari-server/conf/ambari.properties
echo "server.jdbc.driver.path=/usr/share/java/mysql-connector-java.jar" | sudo tee -a /etc/ambari-server/conf/ambari.properties
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
HOSTNAME=$LOCAL_HOSTNAME
#if [ ! -z $MYSQL_VIP ]; then
#  HOSTNAME="$MYSQL_VIP"
#fi

sudo ${CURR_PATH}/cie_setup.sh "$JAVAHOME" "$HOSTNAME" "$MYSQL_PASSWORD"
sleep 3

sudo ambari-server start
sleep 3

exec_cmd all "sudo systemctl stop ambari-agent || true"
exec_cmd all "sudo yum remove -y ambari-agent >/dev/null || true"
exec_cmd all "sudo yum install -y ambari-agent > /dev/null"
exec_cmd all "sudo sed -i 's/^hostname=.*$/hostname=$HOSTNAME/g' /etc/ambari-agent/conf/ambari-agent.ini"
copy_file all "${CURR_PATH}/../config/public_hostname.sh" "/tmp/"
exec_cmd all "sudo mv /tmp/public_hostname.sh /var/lib/ambari-agent/"
exec_cmd all "sudo sed -i '/hostname_script/d' /etc/ambari-agent/conf/ambari-agent.ini"
exec_cmd all "sudo sed -i '/system_resource_overrides=\/etc\/resource_overrides/a public_hostname_script=\/var\/lib\/ambari-agent\/public_hostname.sh' /etc/ambari-agent/conf/ambari-agent.ini"
exec_cmd all "sudo sed -i '/system_resource_overrides=\/etc\/resource_overrides/a hostname_script=\/var\/lib\/ambari-agent\/public_hostname.sh' /etc/ambari-agent/conf/ambari-agent.ini"
exec_cmd all "sudo ambari-agent restart"
