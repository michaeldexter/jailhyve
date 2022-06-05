#jailhyve
Jailed bhyve helper

This is a proof-of-concept to produce a minimum FreeBSD jail for use with the bhyve hypervisor and the scripts to launch the VM.

You are strongly encouraged to run this on a test system or on a nesting hypervisor such as KVM or VMware.


Hard-Coded Variables

nic is em0
VM IP is 10.0.0.111

These will be configurable but you probably want to change them for now


Road Block

/dev/tap0 is not working. Perhaps the issue is obvious to you?

"device emulation initialization error: No such file or directory"

Remove the tap device from bhyve.conf on a 13.1 or later system
or etc/rc on a 12.x or 13.0 system


Requirements

A bootable disk image in <directory>/jailhyve.raw such as a FreeBSD "VM-IMAGE"

A VNC client to view the VM


Usage

sh jailhyve.sh /<path>/<to>/<jail> <jail name>

i.e.

sudo mkdir /tmp/jailhyve
sudo sh jailhyve.sh /tmp/jailhyve jailhyve

To launch the jailed virtual machine:

sh /tmp/jailhyve/launch-jailed-vm.sh

Boot and view the VM with a VNC client such as TigerVNC:

vncviewer 10.0.0.111:5900

Note that bhyve(8) errors are logged to error.log
