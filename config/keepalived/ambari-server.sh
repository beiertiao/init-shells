#!/bin/bash

counter=$(netstat -plan | grep "LISTEN" | grep -c AMBARI_SERVER_PORT)

if [ -f /etc/keepalived/.some_one_as_live ]; then
  if [ ${counter} -eq 0 ]; then
    rm -f /etc/keepalived/.some_one_as_live || true
    systemctl restart keepalived
  fi
fi
