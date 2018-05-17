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

cp "${vmdk}" "vmware_box/box-disk001.vmdk"
cd vmware_box
tar cvzf "../${box}" ./*
rm -f box-disk001.vmdk
cd ..
