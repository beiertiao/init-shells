#!/bin/bash

SUB_CONF="$1"

if [ ! -z "$SUB_CONF" ]; then
  if [ -f /etc/keepalived/keepalived.conf ]; then
    if [ -f /etc/keepalived/$SUB_CONF ]; then
      E=$(grep -c $SUB_CONF /etc/keepalived/keepalived.conf)
      if [ $E -eq 0 ]; then
        echo "" >> /etc/keepalived/keepalived.conf
        echo "include /etc/keepalived/$SUB_CONF" >> /etc/keepalived/keepalived.conf
      fi
    fi
  fi
fi
