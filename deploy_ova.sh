#!/usr/bin/env bash
#######################################################################################################
# Script for deploying an OVA file to a VMware ESXi host using ovftool.
# This script automates the process of deploying a virtual machine from an OVA file,
# setting up basic configurations such as VM name, network, and default gateway.
#
# Usage:
#   ./deploy_ova.sh --host [ESXI_HOST] --user [ESXI_USER] --password [ESXI_PASSWORD] --ova [OVA_FILE] --vm_name [VM_NAME] \
#                   --ip [IP_ADDRESS/NETMASK] --gw [DEFAILT_GW_IP]
#
# If --password option is not defined, the password is prompted on the command line.
# 
# Default values:
#   VM_NAME   - OVA filename without extention
#   ESXI_USER - root
#   IP_ADDRESS-"192.168.1.100/24"
#
# Example:
#   ./deploy_ova.sh --host 192.168.1.100 --user root --password mypassword --ova myvm.ova \
#   --ip 172.20.20.18/24 --gw 172.20.20.1
#
# Requirements:
#   - ovftool must be installed and available in the system's PATH.
#   - genisoimage must be installed and available in the system's PATH.
#   - ESXi host must be accessible and credentials must be valid.
#
# Author: Denis Chertkov, denis@chertkov.info
# version 1.02
# Date: [2025-03-27]
#######################################################################################################

# Exit script on any error
set -e

ESXI_HOST=""
ESXI_USER="root"
ESXI_PASSWORD=""
OVA_FILE=""
# Default values:
VM_NAME=""
IP_ADDRESS="192.168.1.100/24"
DEFAILT_GW_IP=""
LOGFILE="output.log"

echo $(date +%Y-%m-%d-%H:%M:%S) The script started.. > $LOGFILE

# Parse named parameters
while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      ESXI_HOST="$2"
      shift 2
      ;;
    --user)
      ESXI_USER="$2"
      shift 2
      ;;
    --password)
      ESXI_PASSWORD="$2"
      shift 2
      ;;
    --ova)
      OVA_FILE="$2"
      VM_NAME="$(basename "$OVA_FILE" | cut -d. -f1)"
      # echo "VM_NAME: $VM_NAME"
      shift 2
      ;;
    --vm_name)
      VM_NAME="$2"
      shift 2
      ;;
    --ip)
      IP_ADDRESS="$2"
      shift 2
      ;;
    --gw)
      DEFAILT_GW_IP="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 --host [ESXI_HOST] --user [ESXI_USER] --password [ESXI_PASSWORD] --ova [OVA_FILE] --vm_name [VM_NAME] --ip [IP_ADDRESS/SUBNET] --gw [DEFAILT_GW_IP]"
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

# Check the mandatory options
if [ -z "$ESXI_HOST" ] || [ -z "$OVA_FILE" ]; then
  echo "Error: --host, --password and --ova parameters are required!"
  exit 1
fi

if [ ! -d "config" ]; then
    echo -n $(date +%Y-%m-%d-%H:%M:%S) "Directory config does not exist. Creating.. " >> $LOGFILE
    mkdir -p "config"
    echo " Done!" >> $LOGFILE
else
    echo $(date +%Y-%m-%d-%H:%M:%S) "Directory config exists." >> $LOGFILE
fi

if [ ! -d "image" ]; then
    echo -n $(date +%Y-%m-%d-%H:%M:%S) "Directory image does not exist. Creating.. " >> $LOGFILE
    mkdir -p "image"
    echo " Done!" >> $LOGFILE
else
    echo $(date +%Y-%m-%d-%H:%M:%S) "Directory image exists." >> $LOGFILE
fi

# if [ ! -f "config/meta-data" ]; then
cat > "config/meta-data" <<EOF
instance-id: flowsec-local
EOF
# fi

# if [ ! -f "config/user-data" ]; then
cat > "config/user-data" <<EOF
#cloud-config
runcmd:
  - date > /tmp/cloud-config.txt

#cloud-init
bootcmd:
  - echo "Hello, world!" > /tmp/cidata.txt
  - mount /dev/sr0 /mnt && cp /mnt/network.conf /etc/netplan/00-installer-config.yaml && umount /mnt
  - netplan apply
  - date >> /tmp/cidata.txt
EOF
# fi

if [ ! -f "config/network.conf" ]; then
    cat > "config/network.conf" <<EOF
network:
  ethernets:
    ens160:
      addresses: [172.20.1.62/24]
      gateway4: 172.20.1.254
      nameservers:
        addresses:
        - 8.8.8.8
        search: []
  version: 2
EOF
fi

echo $(date +%Y-%m-%d-%H:%M:%S) Start deploying the VM with the next parameters: | tee -a $LOGFILE
echo ESXi host: $ESXI_HOST
echo ESXi user: $ESXI_USER
echo ova: $OVA_FILE
echo VM name: $VM_NAME
echo IP: $IP_ADDRESS
echo GW: $DEFAILT_GW_IP
echo

# Check if ovftool is installed
# if ! command -v ovftool/ovftool &> /dev/null; then
#     echo "Error: ovftool is not installed. Please install it and try again."
#     exit 1
# fi

echo -n $(date +%Y-%m-%d-%H:%M:%S) Prepearing the directory for the new image.. >> $LOGFILE
rm -f image/*.*
echo " Done!" >> $LOGFILE

echo $(date +%Y-%m-%d-%H:%M:%S) Extracting disk images.. >> $LOGFILE
tar xvf $OVA_FILE -C image/ >> $LOGFILE
echo $(date +%Y-%m-%d-%H:%M:%S) Extracting disk Done! >> $LOGFILE

echo -n $(date +%Y-%m-%d-%H:%M:%S) Apply new VM configuration... >> $LOGFILE
sed -i "s|^      addresses:.*|      addresses: [$IP_ADDRESS]|" config/network.conf 
sed -i "s|^      gateway4:.*|      gateway4: $DEFAILT_GW_IP|" config/network.conf 
echo " Done!" >> $LOGFILE

echo $(date +%Y-%m-%d-%H:%M:%S) Creating the new ISO image with a new configuration.. >> $LOGFILE
genisoimage -input-charset utf-8 -log-file genisoimage.log -output image/Stats-N1-file1.iso -volid cidata -joliet -rock -graft-points user-data=config/user-data meta-data=config/meta-data network.conf=config/network.conf
cat genisoimage.log >> $LOGFILE
rm -f genisoimage.log
echo $(date +%Y-%m-%d-%H:%M:%S) Creating the new ISO image Done! >> $LOGFILE

echo -n $(date +%Y-%m-%d-%H:%M:%S) Fixing the OVF.. >> $LOGFILE
len=$(ls -l image/Stats-N1-file1.iso |awk '{print $5}')
news='    <File ovf:href="Stats-N1-file1.iso" ovf:id="file1" ovf:size="'$len'"/>'
sed -i "s|^    <File ovf:href=\"Stats-N1-file1.iso.*|$news|" image/Stats-N1.ovf
echo " Done!" >> $LOGFILE

echo -n $(date +%Y-%m-%d-%H:%M:%S) Fixing the manifest.. >> $LOGFILE
isohashstr="SHA256(Stats-N1-file1.iso)= "$(sha256sum image/Stats-N1-file1.iso|awk '{print $1}')
sed -i "s/^SHA256(Stats-N1-file1.iso.*/$isohashstr/" image/Stats-N1.mf
mfhashstr="SHA256(Stats-N1.ovf)= "$(sha256sum image/Stats-N1.ovf|awk '{print $1}')
sed -i "s/^SHA256(Stats-N1.ovf.*/$mfhashstr/" image/Stats-N1.mf
echo " Done!" >> $LOGFILE

echo $(date +%Y-%m-%d-%H:%M:%S) Creating the new OVA image.. >> $LOGFILE
cd image
tar cvf image.ova Stats-N1.ovf Stats-N1.mf Stats-N1-file1.iso Stats-N1-disk1.vmdk Stats-N1-file2.nvram  >> ../$LOGFILE
cd - > /dev/null
echo $(date +%Y-%m-%d-%H:%M:%S) Creating the new OVA image Done! >> $LOGFILE

echo $(date +%Y-%m-%d-%H:%M:%S) Starting the new VM deploy.. >> $LOGFILE
ovftool/ovftool --noSSLVerify --name=$VM_NAME --diskMode=thin --powerOn image/image.ova "vi://$ESXI_USER:$ESXI_PASSWORD@$ESXI_HOST" 2>&1 | tee -a $LOGFILE
# Log cleanup from progress lines
sed -i '/ progress: /d' $LOGFILE
echo $(date +%Y-%m-%d-%H:%M:%S) All tasks are done! | tee -a $LOGFILE
