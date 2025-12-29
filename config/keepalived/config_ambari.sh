#!/bin/bash

# Ambari Server Details
AMBARISERVER=$(hostname -f)
USER="admin"
PASSWORD=AMBARI_PWD
PORT=AMBARI_PORT
PROTOCOL=http
AS_VIP=AMBARI_VIP

# Load Balancer Details
ACTIVE_AMBARI=$AMBARISERVER

function config_agent()
{
  # Get the cluster name
  CLUSTER=$(curl -ksu $USER:$PASSWORD -i -H 'X-Requested-By: ambari' $PROTOCOL://$AMBARISERVER:$PORT/api/v1/clusters | grep -o '"cluster_name" : "[^"]*' | awk -F'"' '{print $4}')

  # Get the list of all hosts in the cluster
  HOSTS=($(curl -su $USER:$PASSWORD $PROTOCOL://$AMBARISERVER:$PORT/api/v1/clusters/$CLUSTER/hosts | grep -o '"host_name" : "[^"]*' | awk -F'"' '{print $4}'))

  # Loop through each host and update ambari-agent.ini
  for HOST in "${HOSTS[@]}"; do
    # Get current hostname from ambari-agent.ini on remote host
    CURRENT_HOSTNAME=$(ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR $HOST "grep 'hostname=' /etc/ambari-agent/conf/ambari-agent.ini | cut -d'=' -f2")

    # Check if the hostname needs to be updated
    if [ "$CURRENT_HOSTNAME" != "$ACTIVE_AMBARI" ]; then
      # Backup the original ambari-agent.ini file
      ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR $HOST "sudo cp -f /etc/ambari-agent/conf/ambari-agent.ini /etc/ambari-agent/conf/ambari-agent.ini.bak"

      # Update hostname in ambari-agent.ini on remote host
      ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR $HOST "sed -i 's/^hostname=.*/hostname=$ACTIVE_AMBARI/' /etc/ambari-agent/conf/ambari-agent.ini"

      # Restart ambari-agent on remote host
      ssh -o StrictHostKeyChecking=no -o LogLevel=ERROR $HOST "sudo /usr/sbin/ambari-agent restart"
      echo "Hostname on $HOST updated to $ACTIVE_AMBARI. Ambari agent restarted."
    else
      echo "Hostname on $HOST is already set to $ACTIVE_AMBARI. No action needed."
    fi
  done
}

function check_vip_exist()
{
  E=$(ip a | grep -c $AS_VIP)
  if [ $E -ne 0 ]; then
    A_E=$(netstat -plan | grep "LISTEN" | grep -c $PORT)
    if [ $A_E -eq 0 ]; then
      sleep 30
      E=$(ip a | grep -c $AS_VIP)
      if [ $E -ne 0 ]; then
        /usr/sbin/ambari-server start || true
        sleep 5
        touch /etc/keepalived/.some_one_as_live
      fi
    else
      touch /etc/keepalived/.some_one_as_live
    fi
  else
    /usr/sbin/ambari-server stop || true
    test -f /etc/keepalived/.some_one_as_live && rm -f /etc/keepalived/.some_one_as_live
  fi
}

check_vip_exist
