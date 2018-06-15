#!/bin/bash
#
# Package exported Amazon Linux AMI vmdk image into VirtualBox box.
#
# Usage:
#   package-virtualbox-box.sh input-vmdk output-box
#

set -ex

vmdk="$1"
box="$2"
second_volume_size="$3"

vmname="$(basename "${vmdk}" .vmdk)"

# Create VirtualBox vm
VBoxManage createvm --name "${vmname}" --ostype RedHat_64 --register

# Configure vmdk disk
VBoxManage storagectl "${vmname}" --name SATA --add sata --controller IntelAhci
VBoxManage storageattach "${vmname}" --storagectl SATA --port 0 --device 0 --type hdd --medium "${vmdk}"
if [ -n "${second_volume_size}" ]; then
  VBoxManage createmedium disk --filename seconddisk.vmdk --format vmdk --size $(($second_volume_size * 1024))
  VBoxManage storageattach "${vmname}" --storagectl SATA --port 1 --device 0 --type hdd --medium seconddisk.vmdk
fi

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
