#!/usr/bin/expect -f

set MYSQLPWD [lindex $argv 0]

spawn mysql_secure_installation
set timeout 300

expect {
  "Switch to unix_socket authentication*" { send "Y\r"; exp_continue; } 
  "Change the root password*" { send "Y\r"; exp_continue; } 
  "Enter current password for root*" { send "\r"; exp_continue; }  
  "Set root password*" { send "Y\r"; exp_continue; }  
  "New password*" { send "$MYSQLPWD\r"; exp_continue; }  
  "Re-enter new password*" { send "$MYSQLPWD\r"; exp_continue; }
  "Remove anonymous users*" { send "Y\r"; exp_continue; }  
  "Disallow root login remotely*" { send "n\r"; exp_continue; }  
  "Remove test database and access to it*" { send "Y\r"; exp_continue; }  
  "Reload privilege tables now*" { send "Y\r"; exp_continue; }  
}
