#!/bin/bash

counter=$(netstat -plan | grep "LISTEN" | grep -c "3306")
if [ ${counter} -eq 0 ]; then
  systemctl restart keepalived
fi
