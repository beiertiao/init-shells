connector.name=hive-hadoop2
hive.metastore.uri=thrift://{{hive_metastore_hostname}}:9083
hive.config.resources=/etc/hadoop/conf/core-site.xml,/etc/hadoop/conf/hdfs-site.xml
hive.allow-drop-table=true
hive.recursive-directories=true
