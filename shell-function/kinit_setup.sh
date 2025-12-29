#!/usr/bin/expect -f

set DB_MASTER_PWD [lindex $argv 0]

spawn kinit admin/admin
set timeout 300

expect {
  "Password for admin/admin@*:" { send "$DB_MASTER_PWD\n"; exp_continue; }  
}
