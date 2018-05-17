#!/bin/bash
#
# Install guest additions and apply security updates.
#
# Usage:
#   install-guest-additions.sh input-box output-box
#

set -ex

box="$1"
outbox="$2"

name="$(basename "${outbox}" .box)-$$"

# Create temporary vagrant directory.
export VAGRANT_CWD="$(mktemp -d -t "${name}")"

# Ensure vmware-desktop plugin installed.
vagrant plugin list | grep vagrant-vmware-desktop || vagrant plugin install vagrant-vmware-desktop
# Register base box.
vagrant box add --name "${name}" "${box}"

# Install security updates.
# Install compiler and kernel headers required for building guest additions.
cat >"${VAGRANT_CWD}/Vagrantfile" <<EOF
Vagrant.configure(2) do |config|
  config.vm.box = "${name}"
  config.ssh.insert_key = false

  # Do not attempt to install guest additions.
  config.vbguest.auto_update = false
  # Do not attempt to sync folder, dependent on guest additions.
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
  end
  config.vm.provider "vmware_desktop" do |v|
    v.vmx["memsize"] = 1024
  end

  config.vm.provision :shell,
    inline: "sudo yum -y update --security && sudo yum -y install gcc kernel-devel-\$(uname -r)"

  config.vm.provider "vmware_desktop" do |vmware, override|
    # install guest additions and make sure they stay up to date with kernel updates
    override.vm.provision :shell,
      inline: "sudo yum --enablerepo=epel install -y open-vm-tools && echo \"answer AUTO_KMODS_ENABLED yes\" | sudo tee -a /etc/vmware-tools/locations"
  end
end
EOF

vagrant up --provider=vmware_desktop
vagrant halt

# Export box.
vagrant package --output "${outbox}"
vagrant destroy --force

# Unregister base box.
vagrant box remove "${name}" --provider=vmware_fusion

# Clean up temporary vagrant directory.
rm -rf "${VAGRANT_CWD}"
