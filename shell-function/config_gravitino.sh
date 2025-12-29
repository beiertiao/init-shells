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

# kerberos need tmpDir
exec_cmd all "sudo mkdir -p /keytabs && sudo chmod 777 /keytabs"

# https
if [ ! -f /etc/security/gravitino.jks ]; then
  source /etc/profile && keytool -genkeypair  -alias cie -keyalg RSA -keysize 4096 -keypass Cestc_01 -sigalg SHA256withRSA -keystore /etc/security/gravitino.jks -storetype JKS -storepass Cestc_01 -dname "cn=cie,ou=cestc,o=org,l=beijing,st=beijing,c=cn" -validity 36500
  copy_file all "/etc/security/gravitino.jks" "/etc/security/"
fi

# create gravitino admin user
sudo /usr/sbin/kadmin.local -q "addprinc -pw 123456 gravitino-super"

ldapmodify -H ldap://127.0.0.1:389 -D "cn=Manager,dc=cestc,dc=com" -w Cestc_01 << EOF
dn: krbPrincipalName=gravitino-super@CESTC.COM,cn=CESTC.COM,cn=kerberos,dc=cestc,dc=com
changetype: modify
add: objectClass
objectClass: posixAccount
-
add: uid
uid: gravitino-super
-
add: uidNumber
uidNumber: 10001
-
add: gidNumber
gidNumber: 1000
-
add: homeDirectory
homeDirectory: /home/gravitino-super
-
add: cn
cn: gravitino-super
-
add: userPassword
userPassword: 123456
EOF