#!/usr/bin/env python2.7
"""
A minimal builder.
"""

import argparse
import boto3.session
import contextlib
import datetime
import os
import paramiko
import pipes
import scp
import socket
import subprocess
import sys
import time
import uuid

EXPORT_SCRIPT = "scripts/export-vmdk.sh"
PACKAGE_SCRIPT = "scripts/package-vagrant-box.sh"
GUEST_SCRIPT = "scripts/install-guest-additions.sh"
PRIVATE_KEY_FILE = "keypair.pem"

POLL_SECONDS = 5


def get_first(boto_collection):
    """
    Get first item from boto3 collection.
    Cannot use standard next() since boto3 collections are not iterators.
    """
    for resource in boto_collection:
        print "get", repr(resource)
        return resource
    raise Exception("NotFound")


@contextlib.contextmanager
def resource_cleanup(debug=False):
    cleanup_stack = []
    try:
        yield cleanup_stack
    except Exception as e:
        print "exception", e
        if debug:
            raw_input("Press return to continue: ")
        raise
    finally:
        for cleanup_function in reversed(cleanup_stack):
            cleanup_function()


def defer_delete(stack, resource):
    print "create", repr(resource)

    def cleanup():
        print "delete", repr(resource)
        resource.delete()

    stack.append(cleanup)


def defer_terminate(stack, instance):
    print "create", repr(instance)

    def cleanup():
        print "terminate", repr(instance)
        instance.terminate()
        print "wait for termination", repr(instance)
        instance.wait_until_terminated()

    stack.append(cleanup)


# Cache image lookups to speed launch.
image_cache = {}


def get_image(ec2, owner, name):
    key = (owner, name)
    image = image_cache.get(key)
    if not image:
        image = get_first(ec2.images.filter(Owners=[owner], Filters=[{"Name": "name", "Values": [name]}]))
        image_cache[key] = image
    return image


def wait_until_volume_state(volume, state):
    while volume.state != state:
        print "wait", repr(volume), volume.state, "->", state
        time.sleep(POLL_SECONDS)
        volume.reload()


def attach_ebs_image(ec2, instance, image, device_name):
    # Create volume from EBS image root device snapshot.
    volume = ec2.create_volume(SnapshotId=image.block_device_mappings[0]["Ebs"]["SnapshotId"],
                               AvailabilityZone=instance.placement["AvailabilityZone"],
                               VolumeType="gp2")
    print "create", repr(volume)

    wait_until_volume_state(volume, "available")

    # Attach volume.
    volume.attach_to_instance(InstanceId=instance.id,
                              Device=device_name)
    print "attach", repr(volume), "to", repr(instance)

    wait_until_volume_state(volume, "in-use")

    # Ensure volume deleted after instance termination.
    instance.modify_attribute(BlockDeviceMappings=[dict(
            DeviceName=device_name,
            Ebs=dict(DeleteOnTermination=True),
    )])


def connect_ssh(username, host, private_key_file):
    ssh_client = paramiko.SSHClient()
    ssh_client.set_missing_host_key_policy(paramiko.client.AutoAddPolicy())  # TODO: Configure host key fingerprint.
    while not ssh_client.get_transport():
        try:
            ssh_client.connect(host,
                               username=username,
                               key_filename=private_key_file,
                               allow_agent=False,
                               look_for_keys=False,
                               compress=True)
        except socket.error:
            print "wait ssh agent"
            time.sleep(POLL_SECONDS)

    return ssh_client


def provision_file_put(ssh_client, local_file, remote_file):
    print "put", local_file, remote_file
    scp_client = scp.SCPClient(ssh_client.get_transport())
    scp_client.put(local_file, remote_file)
    scp_client.close()


def provision_file_get(ssh_client, remote_file, local_file):
    print "get", remote_file, local_file
    scp_client = scp.SCPClient(ssh_client.get_transport())
    scp_client.get(remote_file, local_file)
    scp_client.close()


def copy_lines(input, output):
    for line in iter(lambda: input.readline(1024), ""):
        output.write(line)


def provision_shell(ssh_client, argv, get_pty=False):
    command = " ".join(pipes.quote(arg) for arg in argv)
    print "shell", command
    stdin, stdout, stderr = ssh_client.exec_command(command, get_pty=get_pty)

    stdin.close()
    copy_lines(stdout, sys.stdout)
    stdout.close()
    copy_lines(stderr, sys.stdout)
    stderr.close()

    retcode = stdout.channel.recv_exit_status()
    if retcode:
        raise subprocess.CalledProcessError(retcode, command)


def local_cmd(cmd):
    print " ".join(cmd)
    subprocess.check_call(cmd)


def get_parser():
    parser = argparse.ArgumentParser()

    parser.add_argument("--debug", action="store_true")

    g = parser.add_argument_group("Input")
    g.add_argument("--ami-owner",
                   default="amazon",
                   help="Source image owner")
    g.add_argument("--ami-name",
                   default="amzn-ami-hvm-2016.09.1.20170119-x86_64-gp2",
                   help="Source image name")

    g = parser.add_argument_group("Builder")
    g.add_argument("--builder-ami-owner",
                   default="amazon",
                   help="Builder image owner")
    g.add_argument("--builder-ami-name",
                   default="amzn-ami-hvm-2016.09.1.20170119-x86_64-gp2",
                   help="Builder image name")
    g.add_argument("--builder-username",
                   default="ec2-user")
    g.add_argument("--region",
                   default="us-east-1")
    g.add_argument("--vpc-id")
    g.add_argument("--vpc-name")
    g.add_argument("--subnet-id")
    g.add_argument("--instance-type",
                   default="c4.large")
    g.add_argument("--device-name",
                   default="/dev/xvdf",
                   help="Attach source image to this device.")

    g = parser.add_argument_group("Provisioner")
    g.add_argument("--yum-proxy",
                   default="")

    g = parser.add_argument_group("Output")
    g.add_argument("--output-prefix", "-o",
                   help="Output path prefix, defaults to AMI_NAME-DATETIME")

    return parser


def main():
    args = get_parser().parse_args()

    prefix = args.output_prefix
    if not prefix:
        prefix = "{source_ami_name}-{dt:%Y%m%d%H%M}".format(source_ami_name=args.ami_name,
                                                            dt=datetime.datetime.utcnow())

    vmdk = prefix + ".vmdk"
    box = prefix + ".box"
    guestbox = prefix + "-guest.box"

    # Allocate run identifier to uniquely name temporary resources.
    run_name = "ectou-export-{run_id}".format(run_id=uuid.uuid4())

    # Create boto session.
    session = boto3.session.Session()
    ec2 = session.resource("ec2", args.region)

    # Resolve source and builder images.
    source_image = get_image(ec2, args.ami_owner, args.ami_name)
    builder_image = get_image(ec2, args.builder_ami_owner, args.builder_ami_name)

    # Resolve VPC if provided, otherwise assume account has default VPC.
    vpc = None
    if args.vpc_id:
        vpc = get_first(ec2.vpcs.filter(VpcIds=[args.vpc_id]))
    elif args.vpc_name:
        vpc = get_first(ec2.vpcs.filter(Filters=[{"Name": "tag:Name", "Values": [args.vpc_name]}]))

    subnet = None
    if vpc:
        if args.subnet_id:
            subnet = get_first(vpc.subnets.filter(SubnetIds=[args.subnet_id]))
        else:
            subnet = get_first(vpc.subnets.all())

    # Set options for explicit VPC, default VPC.
    vpc_id = vpc.id if vpc else ""
    subnet_id = subnet.id if subnet else ""

    with resource_cleanup(args.debug) as cleanup:

        # Create temporary key pair
        key_pair = ec2.create_key_pair(KeyName=run_name)
        defer_delete(cleanup, key_pair)

        # Create temporary security group
        sg = ec2.create_security_group(GroupName=run_name,
                                       Description="Temporary security group for ectou-export",
                                       VpcId=vpc_id)
        defer_delete(cleanup, sg)

        # Enable ssh access
        sg.authorize_ingress(IpPermissions=[dict(
                IpProtocol="tcp",
                FromPort=22,
                ToPort=22,
                IpRanges=[dict(CidrIp="0.0.0.0/0")],
        )])

        # Launch builder EC2 instance
        instance = get_first(ec2.create_instances(ImageId=builder_image.id,
                                                  MinCount=1,
                                                  MaxCount=1,
                                                  KeyName=key_pair.name,
                                                  InstanceType=args.instance_type,
                                                  NetworkInterfaces=[dict(
                                                          DeviceIndex=0,
                                                          SubnetId=subnet_id,
                                                          Groups=[sg.id],
                                                          AssociatePublicIpAddress=True,
                                                  )]))
        defer_terminate(cleanup, instance)

        instance.create_tags(Tags=[{"Key": "Name", "Value": run_name}])
        instance.wait_until_running()

        # Attach source image as device
        attach_ebs_image(ec2, instance, source_image, args.device_name)

        # Save key pair for ssh
        with open(PRIVATE_KEY_FILE, "w") as f:
            os.chmod(PRIVATE_KEY_FILE, 0o600)
            f.write(key_pair.key_material)

        print "To access instance for debugging:"
        print "  ssh -i {} {}@{}".format(PRIVATE_KEY_FILE, args.builder_username, instance.public_ip_address)

        ssh_client = connect_ssh(args.builder_username, instance.public_ip_address, PRIVATE_KEY_FILE)

        # Export device to vmdk
        provision_file_put(ssh_client, EXPORT_SCRIPT, "export.sh")
        provision_shell(ssh_client, ["sudo", "bash", "export.sh", args.device_name, "export.vmdk", args.yum_proxy],
                        get_pty=True)
        provision_file_get(ssh_client, "export.vmdk", vmdk)

    # Package vmdk into vagrant box
    local_cmd(["bash", PACKAGE_SCRIPT, vmdk, box])

    # Install guest additions, apply security updates.
    local_cmd(["bash", GUEST_SCRIPT, box, guestbox])


if __name__ == "__main__":
    main()
