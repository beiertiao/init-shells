[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 EXAMPLE.COM = {
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal arcfour-hmac:normal camellia256-cts:normal camellia128-cts:normal
  database_module = openldap_ldapconf
 }

[dbmodules]
 openldap_ldapconf = {
  db_library = kldap
  ldap_servers = ldap://OPENLDAP_SERVER:389
  ldap_kerberos_container_dn = cn=kerberos,dc=cestc,dc=com
  ldap_kdc_dn = cn=Manager,dc=cestc,dc=com
  ldap_kadmind_dn = cn=Manager,dc=cestc,dc=com
  ldap_service_password_file = /etc/openldap/openldap-manager.keyfile
  ldap_conns_per_server = 5
 }
