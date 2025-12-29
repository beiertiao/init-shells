#!/bin/bash
set -ex

this="${BASH_SOURCE-$0}"
bin=$(cd -P -- "$(dirname -- "${this}")" >/dev/null && pwd -P)
if [[ -f "${bin}/cie_config.sh" ]]; then
  . ${bin}/cie_config.sh
else
  echo "ERROR: Cannot execute ${bin}/cie_config.sh." 2>&1
  exit 1
fi

if [ ! -f $HOST_FILE ]; then
  echo -e "!!! Make sure $HOST_FILE file already configured."
  exit -1
fi

export ARCH=`arch`

trim() {
    str=$1
    echo "${str}" | grep -o "[^ ]\+\( \+[^ ]\+\)*"
}

function valid_ip()
{
    local  ip=$1
    local  stat=1

    match_status=$(echo "$ip"| egrep -c "$IP_REGEX")

    if [ $match_status -eq 1 ]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    echo $stat
}

declare -A HOSTS_INFO
while read line
do
    host_info=$(trim "$line")
    if [ -z "$host_info" ]; then
        echo ignore blank line...
    fi
    ip=$(echo "$host_info" | awk '{print $1}')
    passwd=$(echo "$host_info" | awk '{print $2}')
    if [ $(valid_ip "$ip") -ne 0 ]; then
        echo ip ${ip} is invalid... 
        continue
    fi 
    HOSTS_INFO[${ip}]="$passwd"
done < $HOST_FILE

set -x
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" scp -P ${SSH_PORT} -o StrictHostKeyChecking=no -o LogLevel=ERROR -r /root/.ssh root@$H:/root/; done
