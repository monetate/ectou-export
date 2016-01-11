#!/bin/bash -ex
#
# Example user data script template for a trivial yum proxy.
#
# Launch instance with security group that only allows ingress from your network to port 8888.
# Do NOT launch instances with security groups that are open HTTP relays.
#
yum -y update
yum -y install tinyproxy --enablerepo=epel
sed -i.bak -e 's/^Allow 127.0.0.1/#Allow 127.0.0.1/g' /etc/tinyproxy/tinyproxy.conf
chkconfig tinyproxy on
service tinyproxy start
