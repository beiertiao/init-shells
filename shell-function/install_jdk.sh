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

echo -e "############## install jdk  #####################\n"
if [ x$ARCH = "xaarch64" ]; then
  copy_file all "${CURR_PATH}/../aux-package/jdk/OpenJDK8U-jdk_aarch64_linux_hotspot_8u432b06.tar.gz" "/tmp/"
else
  copy_file all "${CURR_PATH}/../aux-package/jdk/OpenJDK8U-jdk_x64_linux_hotspot_8u432b06.tar.gz" "/tmp/"
fi
exec_cmd all "sudo mkdir -p /usr/share/java/"
copy_file all "${CURR_PATH}/../aux-package/jdk/mysql-connector-java.jar" "/tmp/"
copy_file all "${CURR_PATH}/../aux-package/jdk/jce_policy-8.zip" "/tmp/"
exec_cmd all "(sudo test -d /tmp/UnlimitedJCEPolicyJDK8 && sudo rm -rf /tmp/UnlimitedJCEPolicyJDK8) || true"
exec_cmd all "sudo unzip /tmp/jce_policy-8.zip -d /tmp/"
exec_cmd all "sudo mv /tmp/mysql-connector-java.jar /usr/share/java/"
exec_cmd all "sudo rpm -qa | grep jdk | xargs rpm -e --nodeps || true"
exec_cmd all "sudo sed -i '/JAVA_HOME/d' /etc/profile"
exec_cmd all "sudo sed -i '/JAVA_HOME/d' /etc/environment"
exec_cmd all "sudo sed -i '/JAVA_HOME/d' ~/.bashrc"
exec_cmd all "sudo rm -rf /usr/java/*"
exec_cmd all "sudo mkdir -p /usr/java"

if [ x$ARCH = "xaarch64" ]; then
  exec_cmd all "sudo tar -zxf /tmp/OpenJDK8U-jdk_aarch64_linux_hotspot_8u432b06.tar.gz -C /tmp/"
  exec_cmd all "sudo mv /tmp/jdk8u432-b06 /usr/java/"
  copy_file all "${CURR_PATH}/../config/libleveldbjni.so" "/tmp/"
  exec_cmd all "sudo mv /tmp/UnlimitedJCEPolicyJDK8/*.jar /usr/java/jdk8u432-b06/jre/lib/security/"
  exec_cmd all "sudo mv /tmp/libleveldbjni.so /usr/java/jdk8u432-b06/jre/lib/aarch64/"
  exec_cmd all "sudo sed -i /JAVA_HOME=/d /etc/profile"
  exec_cmd all "sudo sed -i /JAVA_HOME=/d ~/.bashrc"
  exec_cmd all "echo export JAVA_HOME=/usr/java/jdk8u432-b06 | sudo tee -a /etc/profile"
  exec_cmd all "echo export JAVA_HOME=/usr/java/jdk8u432-b06 | sudo tee -a ~/.bashrc"
  exec_cmd all "echo 'export PATH=\$PATH:\$JAVA_HOME/bin' | sudo tee -a /etc/profile"
  exec_cmd all "echo 'export PATH=\$PATH:\$JAVA_HOME/bin' | sudo tee -a ~/.bashrc"
  exec_cmd all "source /etc/profile || /bin/true"
else
  exec_cmd all "sudo tar -zxf /tmp/OpenJDK8U-jdk_x64_linux_hotspot_8u432b06.tar.gz -C /tmp/"
  exec_cmd all "sudo mv /tmp/jdk8u432-b06 /usr/java/"
  exec_cmd all "sudo mv /tmp/UnlimitedJCEPolicyJDK8/*.jar /usr/java/jdk8u432-b06/jre/lib/security/"
  exec_cmd all "sudo sed -i /JAVA_HOME=/d /etc/profile"
  exec_cmd all "sudo sed -i /JAVA_HOME=/d ~/.bashrc"
  exec_cmd all "echo export JAVA_HOME=/usr/java/jdk8u432-b06 | sudo tee -a /etc/profile"
  exec_cmd all "echo export JAVA_HOME=/usr/java/jdk8u432-b06 | sudo tee -a ~/.bashrc"
  exec_cmd all "echo 'export PATH=\$PATH:\$JAVA_HOME/bin' | sudo tee -a /etc/profile"
  exec_cmd all "echo 'export PATH=\$PATH:\$JAVA_HOME/bin' | sudo tee -a ~/.bashrc"
  exec_cmd all "source /etc/profile || /bin/true"
fi
