#!/usr/bin/expect -f

set JAVAHOME [lindex $argv 0]
set HOSTNAME [lindex $argv 1]
set MYSQLPWD [lindex $argv 2]

spawn ambari-server setup
set timeout 300

expect {
  "Configuring database*Enter choice*" { send "3\r"; exp_continue; }  
  "OK to continue*" { send "y\r"; exp_continue; }  
  "Customize user account for ambari-server daemon*" { send "n\r"; exp_continue; }  
  "Do you want to change Oracle JDK*" { send "y\r"; exp_continue; }
  "Enter choice*" { send "2\r"; exp_continue; }  
  "Path to JAVA_HOME:" { send "$JAVAHOME\r"; exp_continue; }  
  "Enable Ambari Server to download and install GPL Licensed LZO packages*" { send "n\r"; exp_continue; }  
  "Enter advanced database configuration*" { send "y\r"; exp_continue; }  
  "Hostname*" { send "$HOSTNAME\r"; exp_continue; }  
  "Port*:" { send "3306\r"; exp_continue; }  
  "Database name*:" { send "ambari\r"; exp_continue; }  
  "Username*:" { send "root\r"; exp_continue; }  
  "Enter Database Password*:" { send "$MYSQLPWD\r"; exp_continue; }  
  "Re-enter password:" { send "$MYSQLPWD\r"; exp_continue; }  
  "Proceed with configuring remote database connection properties*" { send "y\r"; exp_continue; }
}
