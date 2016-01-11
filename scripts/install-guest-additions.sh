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

# Ensure vbguest plugin installed.
vagrant plugin list | grep vagrant-vbguest || vagrant plugin install vagrant-vbguest

# Create temporary vagrant directory.
export VAGRANT_CWD="$(mktemp -d -t "${name}")"

cat >"${VAGRANT_CWD}/Vagrantfile" <<EOF
Vagrant.configure(2) do |config|
  config.vm.box = "${name}"
  config.ssh.insert_key = false
  config.vm.provision :shell,
    inline: "yum -y update --security"
end
EOF

# Register base box.
vagrant box add --name "${name}" "${box}"

# Install guest additions, apply security updates.
vagrant up
vagrant halt

# Install guest additions again in case of kernel security update.
vagrant up
vagrant halt

# Export box.
vagrant package --output "${outbox}"

# Destroy VM.
vagrant destroy --force

# Unregister base box.
vagrant box remove "${name}"

# Clean up temporary vagrant directory.
rm -rf "${VAGRANT_CWD}"
