#!/usr/bin/expect -f

set OPENLDAP_PASSWORD [lindex $argv 0]
set OPENLDAP_SERVER [lindex $argv 1]
set KRB5_REALMS [lindex $argv 2]

spawn kdb5_ldap_util -D cn=Manager,dc=cestc,dc=com -w $OPENLDAP_PASSWORD -H ldap://$OPENLDAP_SERVER:389 create -r $KRB5_REALMS -subtrees dc=cestc,dc=com
set timeout 300

expect {
  "Enter KDC database master key*" { send "$OPENLDAP_PASSWORD\r"; exp_continue; }  
  "Re-enter KDC database master key to*" { send "$OPENLDAP_PASSWORD\r"; exp_continue; }  
}
