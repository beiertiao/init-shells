# Configuration snippets may be placed in this directory as well
includedir /etc/krb5.conf.d/

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 default_realm = EXAMPLE.COM
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 EXAMPLE.COM = {
  kdc = KADMIN_HOST_NAME
  admin_server = KADMIN_HOST_NAME
  master_kdc = KADMIN_HOST_NAME
  database_name = /var/kerberos/krb5kdc/principal
  key_stash_file = /var/kerberos/krb5kdc/.k5.EXAMPLE.COM
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
 }

[domain_realm]
 example.com = EXAMPLE.COM
