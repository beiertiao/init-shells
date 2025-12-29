connector.name=hive
hive.metastore.uri=thrift://METASTORE_HOSTNAME:9083
hive.config.resources=/etc/hadoop/conf/core-site.xml,/etc/hadoop/conf/hdfs-site.xml
hive.allow-drop-table=true
hive.recursive-directories=true

hive.metastore.authentication.type=KERBEROS
hive.metastore.service.principal=hive/METASTORE_HOSTNAME@CESTC.COM
hive.metastore.client.principal=trino/COORDINATOR_HOSTNAME@CESTC.COM
hive.metastore.client.keytab=/etc/trino/trino.keytab

hive.hdfs.authentication.type=KERBEROS
hive.hdfs.impersonation.enabled=true
hive.hdfs.trino.principal=trino/COORDINATOR_HOSTNAME@CESTC.COM
hive.hdfs.trino.keytab=/etc/trino/trino.keytab
