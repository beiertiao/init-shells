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

OPENLDAP_MASTER_HOST="$1"
OPENLDAP_SLAVE_HOST="$2"
ROLE="$3"

function install_openldap()
{
  sudo yum install -y openldap openldap-servers openldap-clients openldap-devel migrationtools >/dev/null || true
  if [ "x$ROLE" = "xMASTER" ]; then
    exec_cmd client "sudo yum install -y openldap >/dev/null || true"
  fi
  sudo cp ${bin}/../config/openldap/slapd.service /usr/lib/systemd/system/
  sudo systemctl daemon-reload || true

  echo "local4.* /var/log/ldap.log" | sudo tee -a /etc/rsyslog.conf
  sudo systemctl restart rsyslog || true
}

function test_user_and_org()
{
  # create test user and group
  sudo groupadd -g 10000 testgroup1 || true
  sudo groupadd -g 10001 testgroup2 || true
  sudo useradd test1 -d /home/test1 -g 10000 || true
  sudo useradd test2 -d /home/test2 -g 10001 || true

  sudo /usr/bin/ldapadd -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD -f ${bin}/../config/openldap/sync/test/base.ldif || true 
  sudo /usr/bin/ldapadd -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD -f ${bin}/../config/openldap/sync/test/users.ldif || true
  sudo /usr/bin/ldapadd -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD -f ${bin}/../config/openldap/sync/test/groups.ldif || true
  sudo /usr/bin/ldapadd -x -D "cn=Manager,dc=cestc,dc=com" -w $OPENLDAP_PASSWORD -f ${bin}/../config/openldap/sync/test/add_user_to_groups.ldif || true
}

function config_openldap()
{
  ## config ldap log
  sudo cp ${bin}/../config/openldap/log.ldif /tmp/
  sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/log.ldif

  NPWD=$(sudo /usr/sbin/slappasswd -s $OPENLDAP_PASSWORD)
  sudo cp -r ${bin}/../config/openldap/schema/*.ldif /etc/openldap/schema/
  sudo mkdir -p /etc/openldap/uldif
  sudo cp -r ${bin}/../config/openldap/domain/*.ldif /etc/openldap/uldif/
  if [ "x$ROLE" = "xMASTER" ]; then
    sudo cp -r ${bin}/../config/openldap/changepwd.ldif /etc/openldap/uldif/
    sudo sed -i "s#PASSWORD#$NPWD#g" /etc/openldap/uldif/changepwd.ldif 
    sudo sed -i "s#PASSWORD#$NPWD#g" /etc/openldap/uldif/chdomain.ldif 
    sudo sed -i "s#PASSWORD#$NPWD#g" /etc/openldap/uldif/basedomain.ldif 
  elif [ "x$ROLE" = "xSLAVE" ]; then
    sudo cp -r /tmp/uldif/*.ldif /etc/openldap/uldif/
  else
    echo "role is unsupport, exit config..."
    exit -1
  fi 
  sudo cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
  sudo chown -R ldap:ldap /var/lib/ldap/DB_CONFIG

  sudo systemctl restart slapd || true

  if [ "x$ROLE" = "xMASTER" ]; then
    sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/uldif/changepwd.ldif
  fi
  sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
  sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
  sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
  sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/openldap.ldif

  sudo /usr/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f /etc/openldap/uldif/chdomain.ldif
  sudo /usr/bin/ldapadd -x -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -f /etc/openldap/uldif/basedomain.ldif

  # config sync
  if [ "x$ROLE" = "xMASTER" ]; then
    sudo cp ${bin}/../config/openldap/sync/configrep.ldif /tmp
    sudo sed -i "s/OPENLDAP_IP/$OPENLDAP_SLAVE_HOST/g" /tmp/configrep.ldif
    sudo sed -i "s/SERVER_ID/1/g" /tmp/configrep.ldif
    sudo sed -i "s/SERVER_INDEX/001/g" /tmp/configrep.ldif
    sudo sed -i "s/PASSWORD/$OPENLDAP_PASSWORD/g" /tmp/configrep.ldif
    sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f ${bin}/../config/openldap/sync/mod_syncprov.ldif
    sudo /usr/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/configrep.ldif
  elif [ "x$ROLE" = "xSLAVE" ]; then
    sudo cp ${bin}/../config/openldap/sync/configrep.ldif /tmp
    sudo sed -i "s/OPENLDAP_IP/$OPENLDAP_MASTER_HOST/g" /tmp/configrep.ldif
    sudo sed -i "s/SERVER_ID/2/g" /tmp/configrep.ldif
    sudo sed -i "s/SERVER_INDEX/002/g" /tmp/configrep.ldif
    sudo sed -i "s/PASSWORD/$OPENLDAP_PASSWORD/g" /tmp/configrep.ldif
    sudo /usr/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f ${bin}/../config/openldap/sync/mod_syncprov.ldif
    sudo /usr/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/configrep.ldif
  else
    echo "role is unsupport, exit config..."
    exit -1
  fi

  test_user_and_org

  sudo systemctl restart slapd || true
}
 
function start_openldap()
{
  sudo systemctl enable slapd || true
  sudo systemctl start slapd || true
}

install_openldap
start_openldap
config_openldap
