#!/bin/bash
#
# Package exported Amazon Linux AMI vmdk image into VMWare box.
#
# Usage:
#   package-vmware-box.sh input-vmdk output-box
#

set -ex

vmdk="$1"
box="$2"
second_volume_size="$3"

cp "${vmdk}" "vmware_box/box-disk001.vmdk"
cd vmware_box
if [ -n "${second_volume_size}" ]; then
  VBoxManage createmedium disk --filename seconddisk.vmdk --format vmdk --size $(($second_volume_size * 1024))
  cp "../vmx_files/doublevolume.vmx" "./vmwarebox.vmx"
else
  cp "../vmx_files/singlevolume.vmx" "./vmwarebox.vmx"
fi
tar cvzf "../${box}" ./*
rm -f box-disk001.vmdk
rm -f vmwarebox.vmx
if [ -n "${second_volume_size}" ]; then
  rm -f seconddisk.vmdk
fi
cd ..
