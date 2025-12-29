#!/bin/bash
set -ex

CURR_PATH=$(readlink -f "$(dirname "$0")")

sudo find $CURR_PATH -name "*.sh" -exec chmod +x {} \;

echo -e "############ step-1: create repo #######################\n" > $HOME/.cie-init-log
sh $CURR_PATH/shell-function/create_repo.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-2: ssh without passwd ################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/ssh_without_passwd.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-3: install infra #####################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/install_infra.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-4: install mysql #####################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/install_mysql.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-5: install jdk #######################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/install_jdk.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-6: install cie #######################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/install_cie_ha.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-7: install kerberos ##################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/install_kerberos.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-8: init gravitino ##################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/config_gravitino.sh >> $HOME/.cie-init-log 2>&1
echo ""

echo -e "############ step-9: init license ##################\n" >> $HOME/.cie-init-log
sh $CURR_PATH/shell-function/config_license.sh >> $HOME/.cie-init-log 2>&1
echo ""
