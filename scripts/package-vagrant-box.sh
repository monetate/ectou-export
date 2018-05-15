#!/bin/bash
#
# Package exported Amazon Linux AMI vmdk image into Vagrant box.
#
# Usage:
#   package-vagrant-box.sh input-vmdk output-box
#

set -ex

vmdk="$1"
box="$2"
vmware_box="$3"

vmname="$(basename "${vmdk}" .vmdk)"

cp "${vmdk}" "vmware_box/box-disk001.vmdk"
cd vmware_box
tar cvzf "../${vmware_box}" ./*
rm -f box-disk001.vmdk
cd ..

# Create VirtualBox vm
VBoxManage createvm --name "${vmname}" --ostype RedHat_64 --register

# Configure vmdk disk
VBoxManage storagectl "${vmname}" --name SATA --add sata --controller IntelAhci
VBoxManage storageattach "${vmname}" --storagectl SATA --port 0 --device 0 --type hdd --medium "${vmdk}"

# Configure network drivers as virtio
for i in 1 2 3 4; do
    VBoxManage modifyvm "${vmname}" --nictype${i} virtio
done

# Configure initial memory
VBoxManage modifyvm "${vmname}" --memory 1024

# Export vagrant box
vagrant package --base "${vmname}" --output "${box}"

# Destroy VirtualBox vm
VBoxManage unregistervm "${vmname}" --delete
