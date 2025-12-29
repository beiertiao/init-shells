#!/usr/bin/expect -f

set OPENLDAP_PASSWORD [lindex $argv 0]

spawn kdb5_ldap_util stashsrvpw -f /etc/openldap/openldap-manager.keyfile "cn=Manager,dc=cestc,dc=com"
set timeout 300

expect {
  "Password for \"cn=Manager,dc=cestc,dc=com*" { send "$OPENLDAP_PASSWORD\r"; exp_continue; }  
  "Re-enter password for \"cn=Manager,dc=cestc,dc=com*" { send "$OPENLDAP_PASSWORD\r"; exp_continue; }  
}
