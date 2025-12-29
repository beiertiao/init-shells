#!/bin/bash

CURR_PATH=$(sudo readlink -f "$(dirname "$0")")

this="${BASH_SOURCE-$0}"
bin=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
if [[ -f "${bin}/cie_config.sh" ]]; then
  . ${bin}/cie_config.sh
else
  echo "ERROR: Cannot execute ${bin}/cie_config.sh." 2>&1
  exit 1
fi

export AMBARI_CLUSTER_NAME=""

function makesue_ambari_server_installed()
{
  E=$(rpm -qa | grep -c ambari-server)
  if [ $E -eq 0 ]; then
    echo "ambari-server not installed!"
    exit -1
  fi
  AMBARI_CLUSTER_NAME=$(curl -ksu $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -H 'X-Requested-By: ambari' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters | grep -o '"cluster_name" : "[^"]*' | awk -F'"' '{print $4}')
}

function makesue_ambari_kerberos_enabled()
{
  HDFS_S_N="hdfs-""${AMBARI_CLUSTER_NAME,,}"
  E=$(kadmin.local -q "listprincs" | grep -c "$HDFS_S_N")
  if [ $E -eq 0 ]; then
    echo "ambari kerberos not enabled!"
    exit -1
  fi
}

function makesure_kdc_credential_validate() 
{
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -H 'X-Requested-By:ambari' -H 'Content-Type:application/json' -X POST -d '{ "Credential" : { "principal" : "admin/admin@'$KRB5_REALMS'", "key": "'$KRB5_PASSWORD'", "type": "temporary" } }' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/credentials/kdc.admin.credential
  sleep 10
}

function add_and_install_component()
{
  COMPONENT_CLIENT="$1"
  HOST_NAME="$2"
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -H 'X-Requested-By:ambari' -X POST -d '{ "host_components" : [{ "HostRoles" : { "component_name": "'$COMPONENT_CLIENT'" } } ] }' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/hosts?Hosts/host_name=$HOST_NAME
  sleep 60
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context": "Install '$COMPONENT_CLIENT'"}, "HostRoles": {"state": "INSTALLED"}}' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/hosts/$HOST_NAME/host_components/$COMPONENT_CLIENT
  sleep 120
}

function refresh_conf_with_rest()
{
  SERVICE_NAME="$1"
  COMPONENT_CLIENT="$2"
  HOST_NAME="$3"
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -X POST -d '{"RequestInfo": {"command": "RESTART", "context": "Refresh '$COMPONENT_CLIENT' conf", "operation_level": {"level":"HOST","cluster_name":"'$AMBARI_CLUSTER_NAME'"}}, "Requests/resource_filters": [ {"service_name":"'$SERVICE_NAME'","component_name":"'$COMPONENT_CLIENT'","hosts":"'$HOST_NAME'"} ] }' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/requests
  sleep 60
}

function install_and_refresh_client()
{
  HOST_NAME="$1"

  add_and_install_component "HDFS_CLIENT" "$HOST_NAME"
  refresh_conf_with_rest "HDFS" "HDFS_CLIENT" "$HOST_NAME"

  add_and_install_component "YARN_CLIENT" "$HOST_NAME"
  refresh_conf_with_rest "YARN" "YARN_CLIENT" "$HOST_NAME"

  add_and_install_component "HIVE_CLIENT" "$HOST_NAME"
  refresh_conf_with_rest "HIVE" "HIVE_CLIENT" "$HOST_NAME"
}

function makesure_hadoop_and_hive_client_installed()
{
  MASTER_HOST=$(grep $MASTER_AMBARI_SERVER_IP /etc/hosts | awk '{print $NF}')
  SLAVE_HOST=$(grep $SLAVE_AMBARI_SERVER_IP /etc/hosts | awk '{print $NF}')

  install_and_refresh_client "$MASTER_HOST"
  install_and_refresh_client "$SLAVE_HOST"
}

function clean_doSet_version()
{
  rm -f $CURR_PATH/doSet_version*
}

makesue_ambari_server_installed
makesue_ambari_kerberos_enabled
makesure_kdc_credential_validate
makesure_hadoop_and_hive_client_installed

function create_dmp_user_use_ambari()
{
  DMP_USER="$1"
  CURR_TIME_MILLIS=$(date "+%s%N" | awk '{print substr($1,1,13)}')
  DATA_BODY="'{ \"username\": \"$DMP_USER\", \"groupName\": \"hadoop\", \"password\": \"$DMP_USER_DEFAULT_PWD\", \"creatTime\": $CURR_TIME_MILLIS, \"updateTime\": $CURR_TIME_MILLIS }'"
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -X POST -H "content-type: application/json" -d "$(eval echo $DATA_BODY)" http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/views/USER_MANAGER/versions/1.0.0/instances/v1/resources/user-manager/user/createUser  
}

function config_with_script()
{
  CONFIG_TYPE="$1"
  KEY="$2"
  VALUE="$3"
  /var/lib/ambari-server/resources/scripts/configs.py -l $AMBARI_SERVER_VIP -t $AMBARI_SERVER_PORT -u admin -p "$AMBARI_SERVER_PASSWORD" -a set -n $AMBARI_CLUSTER_NAME -c $CONFIG_TYPE -k "$KEY" -v "$VALUE" 
}

function get_config_item_with_script()
{
  CONFIG_TYPE="$1"
  KEY="$2"
  /var/lib/ambari-server/resources/scripts/configs.py -l $AMBARI_SERVER_VIP -t $AMBARI_SERVER_PORT -u admin -p "$AMBARI_SERVER_PASSWORD" -a get -n $AMBARI_CLUSTER_NAME -c $CONFIG_TYPE | grep "$KEY"
} 
 
function restart_with_rest()
{
  SERVICE_NAME="$1"
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -X PUT -d '{"RequestInfo": {"context": "Stop '$SERVICE_NAME'"}, "ServiceInfo": {"state": "INSTALLED"}}' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/services/$SERVICE_NAME
  sleep 120 # 2 minutes
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -X PUT -d '{"RequestInfo": {"context": "Start '$SERVICE_NAME'"}, "ServiceInfo": {"state": "STARTED"}}' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/services/$SERVICE_NAME
}

function restart_all_required_service_with_rest()
{
  curl --user $AMBARI_SERVER_USERNAME:$AMBARI_SERVER_PASSWORD -i -X POST -d '{"RequestInfo": {"command": "RESTART", "context": "Restart all required services", "operation_level": "host_component"}, "Requests/resource_filters": [ {"hosts_predicate":"HostRoles/stale_configs=true&HostRoles/cluster_name='$AMBARI_CLUSTER_NAME'"} ] }' http://$AMBARI_SERVER_VIP:$AMBARI_SERVER_PORT/api/v1/clusters/$AMBARI_CLUSTER_NAME/requests
}

function config_hive_db_charset()
{
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table COLUMNS_V2 modify column COMMENT varchar(256) character set utf8;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table TABLE_PARAMS modify column PARAM_VALUE varchar(4000) character set utf8;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table PARTITION_PARAMS modify column PARAM_VALUE varchar(4000) character set utf8;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table PARTITION_KEYS modify column PKEY_COMMENT varchar(4000) character set utf8;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table INDEX_PARAMS modify column PARAM_VALUE varchar(4000) character set utf8;"
  sudo mysql -u root -p"$MYSQL_PASSWORD" -h"$MYSQL_VIP" -e "use hive; alter table DBS modify column \`DESC\` varchar(4000) character set utf8;"
}

function config_hive_db_jdbc_url()
{
  K_V=$(get_config_item_with_script "hive-site" "javax.jdo.option.ConnectionURL")
  if [ ! -z "$K_V" ]; then
    E=$(echo "$K_V" | grep characterEncoding -c)
    if [ $E -eq 0 ]; then
      R_V=$(echo "$K_V" | awk '{print $NF}' | awk -F '"' '{print $2}')
      R_V=$R_V"?useUnicode=true&characterEncoding=UTF-8"
      config_with_script hive-site "javax.jdo.option.ConnectionURL" "$R_V"
    fi
  fi  
}

function config_hbase_user_privilege()
{
  H_USER="$1"
  K_USER="hbase-""${AMBARI_CLUSTER_NAME,,}"
  sudo kinit -kt /etc/security/keytabs/hbase.headless.keytab "$K_USER""@""$KRB5_REALMS"
  PRIVILEGE_CMD="grant '$H_USER', 'RWXCA'"
  echo "$PRIVILEGE_CMD" | /usr/hdp/current/hbase-client/bin/hbase shell -n >/dev/null 2>&1
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "config hbase user $K_USER privilege failed."
    exit -1
  fi
}

function create_trino_kerberos_account()
{
  E=$(sudo kadmin.local -q "listprincs" | grep -c "trino/$COORDINATOR_HOSTNAME")
  if [ $E -eq 0 ]; then
    sudo mkdir -p /etc/trino/
    sudo kadmin.local -q "addprinc -pw $TRINO_KRB5_PASSWORD trino/$COORDINATOR_HOSTNAME" || true
    sudo kadmin.local -q "xst -kt /etc/trino/trino.keytab trino/$COORDINATOR_HOSTNAME" 
    sudo chown trino:root /etc/trino/trino.keytab
    sudo chmod 777 /etc/trino/trino.keytab
    copy_file all "/etc/trino/trino.keytab" "/etc/trino/"
  fi
}

function generate_trino_keystone()
{
  if [ ! -f /etc/security/keytabs/keystore.jks ]; then
    JAVAHOME=`env | grep JAVA_HOME | awk -F '=' '{print $NF}'`
    sudo ${CURR_PATH}/trino_keystone_setup.sh "$JAVAHOME" "$COORDINATOR_HOSTNAME" "$TRINO_KRB5_PASSWORD"
    copy_file all "/etc/security/keytabs/keystore.jks" "/etc/security/keytabs/"
  fi
}

function config_trino_hive_catalog()
{
  sudo cp ${CURR_PATH}/../config/keepalived/hive.properties.tpl /tmp/hive.properties
  sudo sed -i "s/METASTORE_HOSTNAME/$METASTORE_HOSTNAME/g" /tmp/hive.properties
  sudo sed -i "s/COORDINATOR_HOSTNAME/$COORDINATOR_HOSTNAME/g" /tmp/hive.properties
  copy_file all "/tmp/hive.properties" "/etc/trino/coordinator/catalog/"
  copy_file all "/tmp/hive.properties" "/etc/trino/worker/catalog/"
}

function config_for_hdfs()
{
  for DMP_USER in ${DMP_USERS[@]}
  do   	  
    create_dmp_user_use_ambari "$DMP_USER"
    config_with_script core-site "hadoop.proxyuser.$DMP_USER.groups" "*"
    config_with_script core-site "hadoop.proxyuser.$DMP_USER.hosts" "*" 
  done

  config_with_script core-site "hadoop.proxyuser.trino.groups" "*"
  config_with_script core-site "hadoop.proxyuser.trino.hosts" "*"
}

function config_for_hive()
{
  config_with_script hive-site "hive.security.authorization.sqlstd.confwhitelist" "mapred.*|hive.*|mapreduce.*|spark.*|tez.*"
  config_with_script hive-site "hive.security.authorization.sqlstd.confwhitelist.append" "mapred.*|hive.*|mapreduce.*|spark.*|tez.*"
  config_with_script hiveserver2-site "hive.server2.enable.doAs" "true"
  #config_with_script hiveserver2-site "hive.security.authorization.manager" "org.apache.ranger.authorization.hive.authorizer.RangerHiveAuthorizerFactory"

  config_hive_db_charset
  config_hive_db_jdbc_url
}

function config_for_hbase()
{
  for DMP_USER in ${DMP_USERS[@]}
  do
    config_hbase_user_privilege "$DMP_USER"
  done
}

function config_for_kafka()
{
  config_with_script kafka-broker "allow.everyone.if.no.acl.found" "true"
}

function config_for_ranger()
{
  ## enable hdfs ranger plugin
  config_with_script ranger-env "ranger-hdfs-plugin-enabled" "Yes"
  config_with_script ranger-hdfs-plugin-properties "ranger-hdfs-plugin-enabled" "Yes"
  config_with_script ranger-hdfs-plugin-properties "REPOSITORY_CONFIG_USERNAME" "hdfs"
  config_with_script hdfs-site "dfs.permissions.ContentSummary.subAccess" "true"
  config_with_script hdfs-site "dfs.permissions.namenode.inode.attributes.provider.class" "org.apache.ranger.authorization.hadoop.RangerHdfsAuthorizer"

  ## enable yarn ranger plugin
  config_with_script ranger-env "ranger-yarn-plugin-enabled" "Yes"
  config_with_script ranger-yarn-plugin-properties "ranger-yarn-plugin-enabled" "Yes"
  config_with_script yarn-site "yarn.authorization-provider" "org.apache.ranger.authorization.yarn.authorizer.RangerYarnAuthorizer"

  ## enable hive ranger plugin
  config_with_script ranger-env "ranger-hive-plugin-enabled" "Yes"
  config_with_script hiveserver2-site "hive.security.authorization.manager" "org.apache.ranger.authorization.hive.authorizer.RangerHiveAuthorizerFactory"
  config_with_script hive-site "hive.server2.enable.doAs" "true"
  config_with_script hive-env "hive_security_authorization" "Ranger"

  ## enable spark3 ranger plugin
  config_with_script ranger-env "ranger-spark3-plugin-enabled" "Yes"
  config_with_script ranger-spark3-plugin-properties "ranger-spark3-plugin-enabled" "Yes"

  # config for ldap
  config_with_script ranger-admin-site "ranger.authentication.method" "LDAP"
  config_with_script ranger-admin-site "ranger.ldap.url" "ldap://$LOCAL_IP:389"
  config_with_script ranger-admin-site "ranger.ldap.bind.dn" "cn=Manager,dc=cestc,dc=com"
  config_with_script ranger-admin-site "ranger.ldap.bind.password" "$LDAP_PASSWORD"
  config_with_script ranger-admin-site "ranger.ldap.ad.url" "ldap://$LOCAL_IP:389"
  config_with_script ranger-admin-site "ranger.ldap.ad.bind.dn" "cn=Manager,dc=cestc,dc=com"
  config_with_script ranger-admin-site "ranger.ldap.ad.bind.password" "$LDAP_PASSWORD"

  config_with_script ranger-ugsync-site "ranger.usersync.source.impl.class" "org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.url" "ldap://$LOCAL_IP:389"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.binddn" "cn=Manager,dc=cestc,dc=com"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.ldapbindpassword" "$LDAP_PASSWORD"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.user.nameattribute" "uid"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.user.objectclass" "posixAccount"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.user.searchbase" "cn=CESTC.COM,cn=kerberos,dc=cestc,dc=com"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.user.searchscope" "sub"
  config_with_script ranger-ugsync-site "ranger.usersync.ldap.user.groupnameattribute" "memberof, ismemberof"
  config_with_script ranger-ugsync-site "ranger.usersync.group.memberattributename" "member"
  config_with_script ranger-ugsync-site "ranger.usersync.group.nameattribute" "cn"
  config_with_script ranger-ugsync-site "ranger.usersync.group.objectclass" "group"
  config_with_script ranger-ugsync-site "ranger.usersync.group.searchbase" "dc=cestc,dc=com"
}

function config_for_trino_jvm_config()
{
  PROP=$(/var/lib/ambari-server/resources/scripts/configs.py -l $AMBARI_SERVER_VIP -t $AMBARI_SERVER_PORT -u admin -p "$AMBARI_SERVER_PASSWORD" -a get -n $AMBARI_CLUSTER_NAME -c "trino.jvm.config" | grep -v INFO)
  E=$(echo $PROP | jq .properties.content | grep -c "sun.security.krb5.debug")
  if [ $E -eq 0 ]; then
     C=$(echo $PROP | jq .properties.content | sed 's/\"$//')
     A_C="$C\n -Dsun.security.krb5.debug=true\n -Dlog.enable-console=true\n -Djava.security.krb5.conf=/etc/krb5.conf"
     echo '{"properties": {"content": '$A_C'"} }' > /tmp/.jvm.conf.json
     /var/lib/ambari-server/resources/scripts/configs.py -l $AMBARI_SERVER_VIP -t $AMBARI_SERVER_PORT -u admin -p "$AMBARI_SERVER_PASSWORD" -a set -n $AMBARI_CLUSTER_NAME -c "trino.jvm.config" -f /tmp/.jvm.conf.json
  fi
}

function config_for_trino()
{
  create_trino_kerberos_account
  generate_trino_keystone

  config_for_trino_jvm_config

  config_with_script trino.config.properties "http-server.authentication.krb5.keytab" "/etc/trino/trino.keytab"
  config_with_script trino.config.properties "http-server.authentication.krb5.service-name" "trino"
  config_with_script trino.config.properties "http-server.authentication.type" "KERBEROS"
  config_with_script trino.config.properties "http-server.https.enabled" "true"
  config_with_script trino.config.properties "http-server.https.keystore.key" "$TRINO_KRB5_PASSWORD"
  config_with_script trino.config.properties "http-server.https.keystore.path" "/etc/security/keytabs/keystore.jks"
  config_with_script trino.config.properties "http-server.https.port" "7778"
  config_with_script trino.config.properties "http.authentication.krb5.config" "/etc/krb5.conf"
  config_with_script trino.config.properties "internal-communication.https.required" "false"
  config_with_script trino.config.properties "internal-communication.shared-secret" "trino-secret"

  config_trino_hive_catalog
}

# config for hdfs
config_for_hdfs
restart_all_required_service_with_rest
sleep 300

# config for hive
config_for_hive
#restart_all_required_service_with_rest
#sleep 300

# config for hbase
config_for_hbase

# config for kafka
config_for_kafka
restart_all_required_service_with_rest
sleep 120

# config for ranger
config_for_ranger
restart_all_required_service_with_rest
sleep 300

# config for trino
config_for_trino
restart_with_rest TRINO
sleep 120

restart_all_required_service_with_rest
sleep 120
clean_doSet_version
