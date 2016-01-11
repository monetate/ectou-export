ectou-export
============

This project enables running an `Amazon Linux AMI`_ on a local `VirtualBox`_ virtual machine via `Vagrant`_.

Goal
----

Preserve all the benefits of using the `Amazon Linux AMI`_ in production
while minimizing differences between `EC2`_ and local development environments.

Usage
-----

Examples:

.. code-block:: sh

    ./export.py --ami-name amzn-ami-hvm-2014.09.2.x86_64-gp2 [--vpc-name name] [--yum-proxy url]
    ./export.py --ami-name amzn-ami-hvm-2015.03.1.x86_64-gp2 [--vpc-name name] [--yum-proxy url]
    ./export.py --ami-name amzn-ami-hvm-2015.09.1.x86_64-gp2 [--vpc-name name] [--yum-proxy url]

These examples export vagrant box files named ``AMI_NAME-DATETIME.box`` and ``AMI_NAME-DATETIME-guest.box``.

Overview
--------

The ``export.py`` script will::

    launch builder instance
        attach source image volume
        export-vmdk.sh (device -> vmdk)
            chroot - remove aws dependencies
            chroot - add vagrant user
            create vmdk
    download vmdk

    package-vagrant-box.sh (vmdk -> box)
        create virtualbox vm
        package vagrant box

    install-guest-additions.sh (box -> guest box)
        install guest additions
        apply security updates
        package vagrant box


Dependencies
------------

Host software
~~~~~~~~~~~~~

The software has been tested using:

- VirtualBox 5.0.12
- Vagrant 1.8.1
- Python 2.7

  - boto3 1.2.3
  - paramiko 1.16.0
  - scp 0.10.2

Example on MacOS X host using brew:

.. code-block:: sh

    brew tap caskroom/cask
    brew install brew-cask
    brew cask install virtualbox
    brew cask install vagrant

    pip install -r requirements.txt

AWS account and credentials
~~~~~~~~~~~~~~~~~~~~~~~~~~~

AWS account should have default VPC or explicit VPC.  Requires AWS credentials with permissions to:

.. code-block:: javascript

    {
      "Statement": [{
          "Effect": "Allow",
          "Action" : [
            "ec2:DescribeImages",

            "ec2:CreateKeypair",
            "ec2:DeleteKeypair",

            "ec2:CreateSecurityGroup",
            "ec2:AuthorizeSecurityGroupIngress",
            "ec2:DeleteSecurityGroup",
            
            "ec2:CreateVolume",
            "ec2:AttachVolume",
            "ec2:DetachVolume",
            "ec2:DeleteVolume",

            "ec2:RunInstances",
            "ec2:DescribeInstances",
            "ec2:ModifyInstanceAttribute"
            "ec2:TerminateInstances",
            
            "ec2:CreateTags",
          ],
          "Resource" : "*"
      }]
    }

Access to Amazon repositories
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The repository urls are only accessible from within the AWS environment.  To access these repositories locally there
are several options:

#. Use VPN connection to EC2, such as `OpenVPN Access Server`_ with `Tunnelblick`_ client.
#. Launch HTTP proxy in EC2 with security group restricted to your IP addresses, and configure image ``--yum-proxy``.

.. _Amazon Linux AMI: https://aws.amazon.com/amazon-linux-ami/
.. _EC2: https://aws.amazon.com/ec2/
.. _VirtualBox: https://www.virtualbox.org/wiki/Downloads
.. _Vagrant: https://www.vagrantup.com/
.. _OpenVPN Access Server: https://openvpn.net/
.. _Tunnelblick: https://tunnelblick.net/
