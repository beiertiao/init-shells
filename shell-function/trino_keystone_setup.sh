#!/usr/bin/expect -f

set JAVAHOME [lindex $argv 0]
set COORDINATORHOST [lindex $argv 1]
set TRINOPWD [lindex $argv 2]

spawn $JAVAHOME/bin/keytool -genkeypair -alias presto -keyalg RSA -keystore /etc/security/keytabs/keystore.jks
set timeout 300

expect {
  "What is your first and last name*" { send "$COORDINATORHOST\r"; exp_continue; } 
  "What is the name of your organizational unit*" { send "cestc\r"; exp_continue; } 
  "What is the name of your organization?*" { send "org\r"; exp_continue; }  
  "* password*" { send "$TRINOPWD\r"; exp_continue; }  
  "What is the name of your City*" { send "\r"; exp_continue; }  
  "What is the name of your State*" { send "\r"; exp_continue; }  
  "What is the two-letter country code*" { send "\r"; exp_continue; }  
  "Is CN=*correct*" { send "yes\r"; exp_continue; } 
}
