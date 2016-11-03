#!/bin/bash
#
# Export Amazon Linux AMI 2014.09, 2015.03, or 2015.09 image from device to vmdk file.
#
# Usage:
#   export-vmdk.sh input-device output-vmdk [yum-proxy]
#

set -ex

device="$1"
vmdk="$2"
yum_proxy="$3"


### Begin chroot provisioning

# Mount image
MNT=/mnt
mount "${device}1" $MNT

# Add temporary resolv.conf for chroot network access.
cp /etc/resolv.conf $MNT/etc/resolv.conf


### Image part 1. Remove AWS dependencies from Amazon Linux AMI image

# Disable services
#   Disable cloud-init.
#   Disable ntp since using virtualbox guest additions time synchronization.
#
# Pending work: Detailed dissection of ec2-net-utils & ec2-utils.
#
DISABLE_SERVICE="cloud-config cloud-final cloud-init cloud-init-local ntpd ntpdate"
for service in $DISABLE_SERVICE; do
    chroot $MNT chkconfig $service off
done

# Blacklist kernel modules
cat >>$MNT/etc/modprobe.d/blacklist.conf <<EOF
# Avoid VirtualBox console chatter on mouse movements
blacklist evbug
EOF

# Avoid dhclient hang on boot
cat >>$MNT/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOF
DHCLIENTARGS=-nw
EOF

# Pin repository release version to current release
sed -i.bak -e "s/^releasever=latest/#releasever=latest/g" $MNT/etc/yum.conf

# Add yum proxy
if [[ ${yum_proxy} ]]; then
    cat >>$MNT/etc/yum.conf <<EOF
# Add proxy for amazon repository access
proxy=${yum_proxy}
EOF
fi

### Image part 2. Tailor for Vagrant

# Set root password for console debugging
echo "vagrant" | chroot $MNT passwd --stdin root

# Create vagrant user
chroot $MNT useradd vagrant

# Add ssh authorized key
cat >$MNT/tmp/vagrant.pub <<EOF
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
EOF
chroot $MNT install -m 700 -o vagrant -g vagrant -d /home/vagrant/.ssh
chroot $MNT install -m 600 -o vagrant -g vagrant /tmp/vagrant.pub /home/vagrant/.ssh/authorized_keys
rm $MNT/tmp/vagrant.pub

# Enable password-less sudo
cat >$MNT/etc/sudoers.d/vagrant <<EOF
vagrant ALL=(ALL) NOPASSWD: ALL
EOF

# Disable sudo tty requirement
sed -i.bak -e 's/^Defaults    requiretty/#Defaults    requiretty/g' $MNT/etc/sudoers

# Ensure vagrant is able to detect guest as redhat
# https://github.com/mitchellh/vagrant/blob/7caaffbf389fb298840eafb1edcdf554b977182e/plugins/guests/redhat/guest.rb#L7
touch $MNT/etc/redhat-release


### End chroot provisioning

# Remove temporary resolv.conf
rm $MNT/etc/resolv.conf

# Unmount image
umount $MNT


### Convert image to vmdk

# Install VirtualBox rpm to run VBoxManage convertdd
# Warnings about compiling vboxdrv kernel module are expected
wget http://download.virtualbox.org/virtualbox/5.1.8/VirtualBox-5.1-5.1.8_111374_el6-1.x86_64.rpm
echo "756149c11f4cab8f72648c6a3c9e51e7 VirtualBox-5.1-5.1.8_111374_el6-1.x86_64.rpm" | md5sum -c /dev/stdin
rpm -i --nodeps VirtualBox-5.1-5.1.8_111374_el6-1.x86_64.rpm

VBoxManage convertdd "${device}" "${vmdk}" --format VMDK
chmod 644 "${vmdk}"
