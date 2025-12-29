#!/bin/bash

MYSQL_PASSWORD=MYSQL_PWD

function start_mysql_slave()
{
  mysql -u root -p"$MYSQL_PASSWORD" -e "start slave;"
}

start_mysql_slave
