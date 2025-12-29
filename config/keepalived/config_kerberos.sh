#!/bin/bash
  
AS_VIP=AMBARI_VIP
MAX_RETRY=5

function check_vip_exist()
{
  CNT=0
  while [ $CNT -lt $MAX_RETRY ]
  do
    /usr/local/openldap/bin/ldapsearch -H ldap://$AS_VIP:389 -b "dc=cestc,dc=com" -D "cn=Manager,dc=cestc,dc=com" -w Cestc_01 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "wait vip and slapd started."
      sleep 10
    else
      systemctl start kadmin krb5kdc
      break
    fi
    let CNT++
  done
}

KADM_STATUS=$(systemctl is-active kadmin)
KRB5_STATUS=$(systemctl is-active krb5kdc)
if [ x$KADM_STATUS != "xactive" -o x$KRB5_STATUS != "xactive" ]; then
  check_vip_exist
fi
