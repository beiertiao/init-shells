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

if [ -d $HOME/.ssh ]; then
  sudo test -d $HOME/.ssh.bak && sudo rm -rf $HOME/.ssh.bak
  sudo mv -f $HOME/.ssh $HOME/.ssh.bak
fi
sudo mkdir -p $HOME/.ssh
sudo ssh-keygen -f $HOME/.ssh/id_rsa -t rsa -m PEM -N '' >/dev/null

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

sudo cp $HOME/.ssh/id_rsa.pub /tmp
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" scp -P ${SSH_PORT} -o StrictHostKeyChecking=no -o LogLevel=ERROR -r /tmp/id_rsa.pub $USER@$H:/tmp/; done
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" ssh -p ${SSH_PORT} -l $USER -o StrictHostKeyChecking=no -o LogLevel=ERROR $H "sudo mkdir -p $HOME/.ssh"; done
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" ssh -p ${SSH_PORT} -l $USER -o StrictHostKeyChecking=no -o LogLevel=ERROR $H "sudo cat /tmp/id_rsa.pub | sudo tee -a $HOME/.ssh/authorized_keys"; done
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" ssh -p ${SSH_PORT} -l $USER -o StrictHostKeyChecking=no -o LogLevel=ERROR $H "sudo chmod 600 $HOME/.ssh/authorized_keys"; done
for H in ${!HOSTS_INFO[*]}; do sudo sshpass -p "${HOSTS_INFO[$H]}" ssh -p ${SSH_PORT} -l $USER -o StrictHostKeyChecking=no -o LogLevel=ERROR $H "sudo chown $USER:$USER $HOME/.ssh -R"; done
