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

if [ x"$ENABLE_KERBEROS_LDAP" = x"1" ]; then
  echo -e "############ install kerberos ldap###############\n"
else
  echo -e "############ install kerberos ###################\n"
fi

function install_krb5()
{
  sudo systemctl stop kadmin || true
  sudo systemctl stop krb5kdc || true
  sudo yum remove -y krb5-server krb5-server-ldap krb5-client >/dev/null || true
  sudo rm -rf /var/kerberos || true
  if [ ! -z $MYSQL_VIP ]; then
    ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl stop kprop || true"
    ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl stop kadmin || true"
    ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl stop krb5kdc || true"
    ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo yum remove -y krb5-server krb5-server-ldap krb5-client >/dev/null || true"
    ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo rm -rf /var/kerberos || true"
  fi
  exec_cmd client "sudo yum remove -y krb5-client >/dev/null || true"
  sudo yum install -y krb5-libs krb5-server krb5-server-ldap krb5-client >/dev/null
  exec_cmd client "sudo yum install -y krb5-libs krb5-client >/dev/null"
  sudo cp -rf ${bin}/../config/kerberos/k*.service /usr/lib/systemd/system/
  sudo cp -rf ${bin}/../config/kerberos/krb5kdc /etc/logrotate.d/
  sudo chmod 644 /etc/logrotate.d/krb5kdc
}

function config_krb5()
{
  sudo cp ${CURR_PATH}/../config/kdc.conf.tpl /tmp/kdc.conf
  sudo sed -i "s/EXAMPLE.COM/$KRB5_REALMS/g" /tmp/kdc.conf
  sudo mv /tmp/kdc.conf /var/kerberos/krb5kdc/
  sudo chmod 600 /var/kerberos/krb5kdc/kdc.conf

  if [ ! -z $MYSQL_VIP ]; then
    sudo cp ${CURR_PATH}/../config/krb5.conf.ha.tpl /tmp/krb5.conf
    MASTER_KADMIN_HOST_NAME=$(cat /etc/hosts | grep $MASTER_KADMIN_SERVER_IP | awk '{print $NF}')
    SLAVE_KADMIN_HOST_NAME=$(cat /etc/hosts | grep $SLAVE_KADMIN_SERVER_IP | awk '{print $NF}')
    sudo sed -i "s/MASTER_KADMIN_HOST_NAME/$MASTER_KADMIN_HOST_NAME/g" /tmp/krb5.conf
    sudo sed -i "s/SLAVE_KADMIN_HOST_NAME/$SLAVE_KADMIN_HOST_NAME/g" /tmp/krb5.conf
  else
    sudo cp ${CURR_PATH}/../config/krb5.conf.tpl /tmp/krb5.conf
    sudo sed -i "s/KADMIN_HOST_NAME/$LOCAL_HOSTNAME/g" /tmp/krb5.conf
  fi
  sudo sed -i "s/EXAMPLE.COM/$KRB5_REALMS/g" /tmp/krb5.conf
  sudo sed -i "s/example.com/$(echo $KRB5_REALMS | tr '[A-Z]' '[a-z]')/g" /tmp/krb5.conf
  copy_file all "/tmp/krb5.conf" "/tmp/"
  exec_cmd all "sudo mv /tmp/krb5.conf /etc/" 
  exec_cmd all "sudo chmod 644 /etc/krb5.conf" 
  sudo ${CURR_PATH}/krb5_setup.sh "$KRB5_PASSWORD"
  sleep 10
  echo "*/admin@$KRB5_REALMS *" | sudo tee /var/kerberos/krb5kdc/kadm5.acl
  sleep 3
}

function config_krb5_openldap()
{
  sudo cp ${CURR_PATH}/../config/kdc.conf.openldap.tpl /tmp/kdc.conf
  sudo sed -i "s/EXAMPLE.COM/$KRB5_REALMS/g" /tmp/kdc.conf
  sudo sed -i "s/OPENLDAP_SERVER/$MYSQL_VIP/g" /tmp/kdc.conf
  sudo mv /tmp/kdc.conf /var/kerberos/krb5kdc/
  sudo chmod 600 /var/kerberos/krb5kdc/kdc.conf
}

function start_krb5_and_check()
{
  sudo systemctl enable krb5kdc
  sudo systemctl start krb5kdc
  sudo systemctl enable kadmin
  sudo systemctl start kadmin
  sudo systemctl enable sssd-kcm || true
  sudo systemctl start sssd-kcm || true
  sleep 3
  sudo /usr/sbin/kadmin.local -q "addprinc -pw $KRB5_PASSWORD admin/admin"
  sudo ${CURR_PATH}/kinit_setup.sh "$KRB5_PASSWORD"
  sudo /usr/bin/klist | grep -c "admin/admin@$KRB5_REALMS" > /tmp/klist_status
  RES=$(cat /tmp/klist_status)
  if [ x"$RES" != x"1" ]; then
    echo "kadmin install failed."
    exit 1
  fi 
  sudo mkdir -p /etc/security/keytabs
  sudo rm -f /etc/security/keytabs/krb5.keytab || true
  sudo /usr/sbin/kadmin.local -q "xst -norandkey -k /etc/security/keytabs/krb5.keytab admin/admin"
  sudo kinit -kt /etc/security/keytabs/krb5.keytab admin/admin
}

function start_krb5()
{
  sudo systemctl start krb5kdc
  sudo systemctl start kadmin
  sleep 3
}

function stop_krb5()
{
  sudo systemctl stop krb5kdc
  sudo systemctl stop kadmin
  sleep 3
}
 
function restart_krb5()
{
  sudo systemctl restart krb5kdc
  sudo systemctl restart kadmin
  sleep 3
}

function install_kerberos()
{
  install_krb5
  config_krb5
  start_krb5_and_check
}

function install_and_kerberos()
{
  install_krb5
  config_krb5
}

function clean_openldap()
{
  MASTER_IP="$1"
  SLAVE_IP="$2"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo systemctl stop slapd || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo yum remove -y openldap-servers openldap-clients openldap-devel migrationtools >/dev/null || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -rf /etc/openldap || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -rf /var/lib/ldap || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -rf /usr/share/openldap-servers || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -rf /usr/libexec/openldap || true"
  ssh -l $USER -p ${SSH_PORT} $MASTER_IP "sudo rm -f /usr/lib/tmpfiles.d/slapd.conf || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo systemctl stop slapd || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo yum remove -y openldap-servers openldap-clients openldap-devel migrationtools >/dev/null || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -rf /etc/openldap || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -rf /var/lib/ldap || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -rf /usr/share/openldap-servers || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -rf /usr/libexec/openldap || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo rm -f /usr/lib/tmpfiles.d/slapd.conf || true"
}

function clean_test_user_and_group()
{
  for G in $(grep dn ${bin}/../config/openldap/sync/test/groups.ldif | awk '{print $NF}')
  do
    sudo /usr/bin/ldapdelete -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD "$G"
  done
  for U in $(grep dn ${bin}/../config/openldap/sync/test/users.ldif | awk '{print $NF}')
  do
    sudo /usr/bin/ldapdelete -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD "$U"
  done
}

function install_openldap()
{
  MASTER_IP="$1" 
  SLAVE_IP="$2"
  MASTER_HOST=$(grep $MASTER_IP[[:space:]] /etc/hosts | awk '{print $NF}')
  SLAVE_HOST=$(grep $SLAVE_IP[[:space:]] /etc/hosts | awk '{print $NF}')
  . ${bin}/install_openldap.sh $MASTER_HOST $SLAVE_HOST MASTER
  sudo ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo mkdir -p /tmp/ldap"
  sudo scp -P ${SSH_PORT} -r ${bin}/../shell-function/install_openldap.sh ${bin}/../shell-function/cie_config.sh $USER@${SLAVE_IP}:/tmp/ldap/
  sudo scp -P ${SSH_PORT} -r ${bin}/../config $USER@${SLAVE_IP}:/tmp/
  sudo scp -P ${SSH_PORT} -r /etc/openldap/uldif $USER@${SLAVE_IP}:/tmp/
  ssh -l $USER -p ${SSH_PORT} $SLAVE_IP "sudo sh /tmp/ldap/install_openldap.sh $MASTER_HOST $SLAVE_HOST SLAVE"

  sleep 10

  sudo /usr/bin/ldapsearch -h $MASTER_IP -b "dc=cestc,dc=com" -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD | grep dn > /tmp/master_openldap_status
  sudo /usr/bin/ldapsearch -h $SLAVE_IP -b "dc=cestc,dc=com" -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD | grep dn > /tmp/slave_openldap_status

  diff /tmp/master_openldap_status /tmp/slave_openldap_status >/dev/null
  STATUS=$?
  if [ $STATUS -ne 0 ]; then
    echo "openldap master and slave sync failed, please check file: /tmp/master_openldap_status, /tmp/slave_openldap_status."
    exit -1
  fi

  sleep 3
  clean_test_user_and_group
}

function install_openldap_ha()
{
  SLAVE_IP=`cat ${HOST_FILE} | grep -v $LOCAL_IP[[:space:]] | head -n1 | awk '{print $1}'`
  clean_openldap $LOCAL_IP $SLAVE_IP
  sleep 3
  install_openldap $LOCAL_IP $SLAVE_IP
  sleep 3
  . ${bin}/install_npldapd.sh
}

function load_openldap_kerberos()
{
  sudo cp ${bin}/../config/openldap/kerberos.openldap.ldif /etc/openldap/schema/
  sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/kerberos.openldap.ldif || true 
  sudo cp ${bin}/../config/openldap/addkadmin.ldif ${bin}/../config/openldap/addkrb5kdc.ldif /tmp/
  sudo cp ${bin}/../config/openldap/addaccess.ldif /etc/openldap/schema/
  sudo sed -i "s/PASSWORD/$KRB5_PASSWORD/g" /tmp/addkadmin.ldif
  sudo sed -i "s/PASSWORD/$KRB5_PASSWORD/g" /tmp/addkrb5kdc.ldif
  sudo mv /tmp/addkadmin.ldif /tmp/addkrb5kdc.ldif /etc/openldap/schema/
  sudo ldapadd -H ldap://$LOCAL_HOSTNAME:389 -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -f /etc/openldap/schema/addkadmin.ldif || true
  sudo ldapadd -H ldap://$LOCAL_HOSTNAME:389 -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -f /etc/openldap/schema/addkrb5kdc.ldif || true
  sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/addaccess.ldif || true
}

function load_slave_openldap_kerberos()
{
  sudo scp -P ${SSH_PORT} -r /etc/openldap/schema/kerberos.openldap.ldif /etc/openldap/schema/addkadmin.ldif /etc/openldap/schema/addkrb5kdc.ldif /etc/openldap/schema/addaccess.ldif  $USER@${SLAVE_KADMIN_SERVER_IP}:/etc/openldap/schema/
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/kerberos.openldap.ldif || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo ldapadd -H ldap://$SLAVE_KADMIN_SERVER_IP:389 -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -f /etc/openldap/schema/addkadmin.ldif || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo ldapadd -H ldap://$SLAVE_KADMIN_SERVER_IP:389 -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -f /etc/openldap/schema/addkrb5kdc.ldif || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/addaccess.ldif || true"
}

function install_slave_krb5()
{
  load_slave_openldap_kerberos
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo yum install -y krb5-server krb5-server-ldap"
  sudo cp ${CURR_PATH}/../config/kdc.conf.openldap.tpl /tmp/kdc.conf
  sudo sed -i "s/EXAMPLE.COM/$KRB5_REALMS/g" /tmp/kdc.conf
  sudo sed -i "s/OPENLDAP_SERVER/$MYSQL_VIP/g" /tmp/kdc.conf
  sudo scp -P ${SSH_PORT} -r /tmp/kdc.conf $USER@${SLAVE_KADMIN_SERVER_IP}:/var/kerberos/krb5kdc/
  sudo scp -P ${SSH_PORT} -r ${CURR_PATH}/../config/kerberos/*.service $USER@${SLAVE_KADMIN_SERVER_IP}:/usr/lib/systemd/system/
  sudo scp -P ${SSH_PORT} -r /var/kerberos/krb5kdc/kadm5.acl /var/kerberos/krb5kdc/.k5.$KRB5_REALMS $USER@${SLAVE_KADMIN_SERVER_IP}:/var/kerberos/krb5kdc/
  sudo scp -P ${SSH_PORT} -r /etc/openldap/openldap-manager.keyfile $USER@${SLAVE_KADMIN_SERVER_IP}:/etc/openldap/
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo rm -rf /etc/security/keytabs || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl enable kadmin krb5kdc"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo mkdir -p /etc/security/keytabs"
  sudo scp -P ${SSH_PORT} -r /etc/security/keytabs/krb5.keytab $USER@${SLAVE_KADMIN_SERVER_IP}:/etc/security/keytabs/
  SLAVE_KADMIN_HOST_NAME=$(cat /etc/hosts | grep $SLAVE_KADMIN_SERVER_IP | awk '{print $NF}')
  sudo ${CURR_PATH}/generate_openldap_kerberos_db.sh $OPENLDAP_PASSWORD $SLAVE_KADMIN_HOST_NAME $KRB5_REALMS
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl enable sssd-kcm"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl start sssd-kcm || true"
  ssh -l $USER -p ${SSH_PORT} $SLAVE_KADMIN_SERVER_IP "sudo systemctl start kadmin krb5kdc"
}

if [ x"$ENABLE_KERBEROS_LDAP" = x"1" -a x"$ENABLE_KERBEROS" = x"1" ]; then
  echo "ENABLE_KERBEROS_LDAP and ENABLE_KERBEROS and not be true at the same time..."
  exit -1
fi

if [ x"$ENABLE_KERBEROS_LDAP" = x"1" ]; then

  install_openldap_ha
  load_openldap_kerberos
  install_and_kerberos
  sudo ${CURR_PATH}/generate_manager_keyfile.sh $OPENLDAP_PASSWORD
  config_krb5_openldap
  sudo ${CURR_PATH}/generate_openldap_kerberos_db.sh $OPENLDAP_PASSWORD $LOCAL_HOSTNAME $KRB5_REALMS
  start_krb5_and_check
  if [ ! -z $MYSQL_VIP ]; then
    install_slave_krb5
  fi

  echo "install kerberos ldap succ."
elif [ x"$ENABLE_KERBEROS" = x"1" ]; then

  install_kerberos
  echo "install kerberos succ."
else
  echo "disable kerberos, skip..."
fi
