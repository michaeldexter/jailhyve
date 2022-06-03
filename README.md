# jailhyve
Jailed bhyve helper

This is a proof-of-concept to produce a minimum FreeBSD jail for use with the bhyve hypervisor and the scripts to launch the VM.

You are strongly encouraged to run this on a test system or on a nesting hypervisor such as KVM or VMware.


Road Block

/dev/tap0 is not working. Perhaps the issue is obvious to you?

"device emulation initialization error: No such file or directory"

exec.prepare is not executing


Requirements

A FreeBSD 13.0 or 13.1 host. It may work on 12.*

A bootable disk image in <directory>/jailhyve.raw

Consider using a stock FreeBSD "VM-IMAGE"


Usage

sh jailhyve.sh /<path>/<to>/<jail> <jail name>

i.e.

sudo mkdir /tmp/jailhyve
sudo sh jailhyve.sh /tmp/jailhyve jailhyve

Note that bhyve(8) errors are logged to error.log
