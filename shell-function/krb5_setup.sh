#!/usr/bin/expect -f

set DB_MASTER_PWD [lindex $argv 0]

spawn kdb5_util create -s
set timeout 300

expect {
  "Enter KDC database master key*:" { send "$DB_MASTER_PWD\r"; exp_continue; }  
  "Re-enter KDC database master key to*:" { send "$DB_MASTER_PWD\r"; exp_continue; }  
}
