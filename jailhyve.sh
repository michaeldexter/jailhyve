#!/bin/sh
# Copyright 2022 Michael Dexter <editor@callfortesting.org>
# Published under a two-clause BSD copyright as per the GitHub project at
# https://github.com/michaeldexter/jailhyve

# This is a highly verbose proof-of-concept at this stage
# It aims to be reduced a transparent -j flag for bhyve(8)

# Note the DEBUG "reads" and listings you can uncomment to have it pause at
# several steps to review the output

# TO DO

# Lots
# Fix tap0 failing with:
# "device emulation initialization error: No such file or directory"
# Cleanup is not destroy /dev/vmm/jailhyve


# HARD CODED VARIABLES

host_nic="em0"
# Hard coded for now

# REQUIREMENTS
essential_directories="/dev /etc /tmp"
essential_files="/libexec/ld-elf.so.1 /boot/userboot.so"
essential_utilities="bhyve bhyvectl bhyveload iasl pkill sh ls rm truss id file"
optional_utilities="grub-bhyve"
optional_directories="/usr/local/share/uefi-firmware"


# PREFLIGHT
[ $2 ] || { echo Usage: jailhyve.sh \<directory\> \<VM name\> ; exit 1 ; }
[ -d $1 ] || { echo $1 does not exist ; exit 1 ; }
[ -w $1 ] || { echo $1 is not writable ; exit 1 ; }

if [ "$1" = "/" ] ; then
	echo You REALLY, REALLY do not want to install to '/'
	echo The clean-up will obliterate your system
	exit 1
fi


# DETERMINE HOST VERSION

# 12* introduced jailing support
# 13.1 introduced bhyve_config
 
version=$( freebsd-version | cut -d - -f1 )
major_version=$( echo $version | cut -d . -f1 )

[ "$major_version" -le "11" ] && \
	{ echo FreeBSD 11.* and earlier are not supported ; exit 1 ; }

# BRUTAL CLEANUP WHILE EXPERIMENTAL

echo Performing cleanup
[ -d $1 ] || mkdir $1
# Handling these individually as we do not want to remove the disk image
[ -d $1 ] && chflags -R 0 $1/*
# Make this a loop with an actual test...
umount $1/dev > /dev/null 2>&1
umount $1/dev > /dev/null 2>&1
umount $1/dev > /dev/null 2>&1
umount $1/dev > /dev/null 2>&1

echo Deleting devfs rulesets
devfs rule -s 100 delset
devfs rule -s 100 show

# All this not to remove the VM image. Terrible but works for now
rm -rf $1/bin
rm -rf $1/boot
rm -rf $1/dev
rm -rf $1/etc
rm -rf $1/usr
rm -rf $1/lib
rm -rf $1/libexec
rm -rf $1/tmp
rm $1/bhyve*
rm $1/e*
rm $1/jail.conf # Do not remove jailhyve.raw!

[ $( which tree ) ] && tree $1


echo ; echo ESSENTIAL DIRECTORIES ; echo

for directory in $essential_directories ; do
	mkdir -p ${1}$directory || \
		{ echo mkdir -p ${1}$directory failed ; exit 1 ; }
done

echo ; echo ESSENTIAL FILES ; echo

for file in $essential_files ; do
#	echo DEBUG Working on $file
	file_dir=$( dirname $file )
	mkdir -p ${1}$file_dir || \
		{ echo mkdir -p $file_dir failed ; exit 1 ; }
#	[ -f ${1}$file ] && chflags 0 ${1}$file
	if ! [ -f ${1}$file ] ; then
		cp -npv $file ${1}${file_dir}/ || \
			{ echo $file failed to copy to ${1}${file_dir}/ ; exit 1 ; }
	fi
done

echo ; echo ESSENTIAL UTILITIES; echo

for utility in $essential_utilities ; do
#	echo DEBUG Working on $utility
	util_path=$( which $utility || { echo $utility missing ; exit 1 ; } )
	util_dir=$( dirname $util_path )
	mkdir -p ${1}$util_dir || \
		{ echo mkdir -p $util_dir failed ; exit 1 ; }
#	[ -f ${1}$utility ] && chflags 0 ${1}$utility
	if ! [ -f ${1}$utility ] ; then
		cp -npv $util_path ${1}${util_dir}/ || \
			{ echo $util_path failed to copy  ; exit 1 ; }
	fi

# NOTE THE KLUGE TO GET AROUND 14-CURRENT vdso breaking ldd output
#ldd -f '%p\n' `which bhyve`
#/usr/lib/libvmmapi.so.5
#...
#/lib/libc.so.7
#[preloaded]
#	[vdso] (0x7ffffffff5d0)

	util_deps=$( ldd -f '%p\n' $util_path | grep -v "\[" )
	for util_dep in $util_deps ; do 
		dep_dir=$( dirname $util_dep )
		# mkdir -p will create "as required"
		mkdir -p ${1}$dep_dir || \
			{ echo mkdir -p ${1}$dep_dir failed ; exit 1 ; }
		if ! [ -f ${1}$util_dep ] ; then
			cp -npv $util_dep ${1}${dep_dir}/ || \
				{ echo cp -npv $util_dep failed ; exit 1 ; }	
		fi
	done
done

echo ; echo OPTIONAL UTILITIES ; echo

for utility in $optional_utilities ; do
#	echo DEBUG Working on $utility
	util_path=$( which $utility )
	util_dir=$( dirname $util_path )
	mkdir -p ${1}$util_dir || \
		{ echo mkdir -p $util_dir failed ; exit 1 ; }
# Consider -n no overwrite but a developer might be developing
	cp -npv $util_path ${1}${util_dir}/ || \
		{ echo $util_path failed to copy  ; exit 1 ; }
	
# NOTE THE CRAP KLUGE TO GET AROUND 14-CURRENT vdso breaking ldd output
	util_deps=$( ldd -f '%p\n' $util_path | grep -v "\[" )
#	IFS=" "
	for util_dep in $util_deps ; do 
		dep_dir=$( dirname $util_dep )
		# mkdir -p will create "as required"
		mkdir -p ${1}$dep_dir || \
			{ echo mkdir -p ${1}$dep_dir failed ; exit 1 ; }
		if ! [ -f ${1}$util_dep ] ; then
			cp -npv $util_dep ${1}${dep_dir}/ || \
				{ echo cp -npv $util_dep failed ; exit 1 ; }	
		fi
	done
done

echo ; echo OPTIONAL DIRECTORIES ; echo

for directory in $optional_directories ; do
# Going with simple tests for now
	if ! [ -d ${1}$directory ] ; then
		mkdir -p ${1}$directory
		cp -rp ${directory}/* ${1}${directory}/ || \
			{ echo cp -rp ${directory} failed ; exit 1 ; }
	fi
done

echo Generating the exec.prepare script
cat << EOF > ${1}/exec.prepare
#!/bin/sh
echo Entering exec.prepare on the host

kldstat -q -m vmm || kldload vmm
kldstat -q -m vmm || { echo vmm failed to load ; exit 1 ; }
kldstat -q -m vmm || { echo vmm failed to load ; exit 1 ; }
echo Loading nmdm if needed
kldstat -q -m nmdm || kldload nmdm
kldstat -q -m nmdm || { echo nmdm failed to load ; exit 1 ; }

echo Tearing down VM networking and re-creating

# Sure would be nice to have an ifconfig -q test to determine if an interface
# exists, no more, no less

[ -e /dev/tap0 ] && ifconfig tap0 destroy
[ -e /dev/bridge0 ] && ifconfig bridge0 destroy

echo Building up VM networking

ifconfig tap0 create
ifconfig bridge0 create
ifconfig bridge0 addm em0
ifconfig bridge0 addm tap0 
ifconfig bridge0 up

ifconfig bridge0

# Not preserving the state of these

echo Setting net.link.tap.up_on_open=1
sysctl net.link.tap.up_on_open=1
#net.link.tap.user_open=1

#echo Exiting exec.prepare on the host
#echo DEBUG Look good? ; read good
exit 0
EOF

#cat ${1}/exec.prepare


echo Generating the exec.prestart script
cat << EOF > ${1}/exec.prestart
#!/bin/sh
echo Entering exec.prestart on the host

echo Destroying /dev/vmm/jailhyve if needed
[ -e /dev/vmm/jailhyve ] && { bhyvectl --destroy --vm=jailhyve ; sleep 2 ; }

echo Destroying the devfs rules with devfs rule -s 100 delset
devfs rule -s 100 delset

echo running devfs rule -s 100 show
devfs rule -s 100 show

# Tight
devfs rule -s 100 add path vmm.io unhide
devfs rule -s 100 add path vmm.io/jailhyve.bootrom unhide
devfs rule -s 100 add path vmm/jailhyve unhide
devfs rule -s 100 add path tap0 unhide
devfs rule -s 100 add path nmdm1A unhide

# Loose
#devfs rule -s 100 add path vmm.io unhide
#devfs rule -s 100 add path vmm.io/* unhide
#devfs rule -s 100 add path vmm unhide
#devfs rule -s 100 add path vmm/* unhide
#devfs rule -s 100 add path tap* unhide
#devfs rule -s 100 add path nmdm* unhide

echo running devfs rule -s 100 show
devfs rule -s 100 show

#echo DEBUG Look good? ; read good

#echo DEBUG looking for cu/nmdm processes
#ps | grep nmdm
#ps | grep cu

#echo Exiting exec.prestart on the host
#echo DEBUG Look good? ; read good
exit 0
EOF

#cat ${1}/exec.prestart


echo Generating jail.conf
# Lessons
# exec.clean; fails with getpwnam: No such file or directory

cat << EOF > ${1}/jail.conf
jailhyve {
# Verify all of these, considering that tap0 is not working
	devfs_ruleset = 4;
	devfs_ruleset = 100;
	allow.vmm;
	allow.raw_sockets;
#	persist;
	host.hostname = jailhyve;
	ip4.addr = 10.0.0.111;
	interface = "em0";
	path = "$1";
	mount.devfs;
	exec.prepare = "/bin/sh -x $1/exec.prepare";
	exec.prestart = "/bin/sh -x $1/exec.prestart";
	exec.start = "/bin/sh -x /etc/rc";
	exec.stop = "/bin/sh -x /etc/rc.shutdown jail";
	exec.poststop = "/bin/sh -x $1/exec.poststop";
#	vnet;
}
EOF

#cat ${1}/jail.conf

#echo DEBUG Look good? ; read good

echo Generating the etc/rc script header
cat << EOF > ${1}/etc/rc
#!/bin/sh
set -x
echo Executing /etc/rc in the jail

echo DEBUG Listing Directories
ls /

[ -e /dev/tap0 ] || { ls /dev/tap* ; echo tap device missing? ; }
[ -e /dev/nmdm1A ] && { ls /dev/nmdm* ; echo nvmd1A not generated ; }
[ -d /dev/vmm ] && ls /dev/vmm/*

#echo DEBUG Listing /dev
#ls /dev
#echo DEBUG Look good? ; read good


echo Executing the bhyve command
# Loop syntax from vmrun.sh
# Disabling it for debugging, note the two dones that close it
#while [ 1 ]; do

	# FYI: an ampersand at the next of this will panic the host:
EOF
# Splitting the rc script generation to handle with/without bhyve_config

echo Generating the etc/rc script footer

if [ "$major_version" = "12" -o "$version" = "13.0" ] ; then
	echo bhyve_config support not detected

	cat << EOF >> ${1}/etc/rc
bhyve -c 1 -m 1024 -A -H -P \\
        -s 0,hostbridge \\
        -s 31,lpc \\
        -l com1,stdio \\
        -s 2,virtio-blk,jailhyve.raw \\
        -s 3,virtio-net,tap0 \\
        -l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
        -s 30:0,fbuf,tcp=0.0.0.0:5900,w=640,h=480,wait \\
        -s 30:1,xhci,tablet \\
        jailhyve 2> /error.log

# Removing the null modem device while testing
# 	-l com1,/dev/nmdm1A \\
# Alternatively
#        -l com1,stdio \\

	bhyve_exit=\$?
	if [ \$bhyve_exit -ne 0 ]; then
		break
		# Verify if this is terminating the process/VM/Jail
		exit
	fi
#done

echo Exiting /etc/rc in the jail
exit 0
EOF
else
	echo bhyve_config support detected
echo Generating bhyve.conf

bhyve -o config.dump=1 \
	-c 1 -m 1024 -A -H -P \
	-s 0,hostbridge \
	-s 31,lpc \
	-l com1,stdio \
	-s 2,virtio-blk,jailhyve.raw \
	-s 3,virtio-net,tap0 \
	-l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \
	-s 30:0,fbuf,tcp=0.0.0.0:5900,w=640,h=480,wait \
	-s 30:1,xhci,tablet \
	jailhyve | grep -v config.dump > ${1}/bhyve.conf

# Removing the null modem device while testing
#	-l com1,/dev/nmdm1A \
# Alternatively
#	-l com1,stdio \

#	cat ${1}/bhyve.conf
#echo DEBUG Look good? ; read good

	# Generate the etc/rc footer
	cat << EOF >> ${1}/etc/rc
	/usr/sbin/bhyve -k /bhyve.conf 2> /error.log

	bhyve_exit=\$?
	if [ \$bhyve_exit -ne 0 ]; then
		break
		# This is not terminating the process/VM/Jail
		exit
	fi
#done

echo Exiting /etc/rc in the jail
exit 0
EOF
fi

#cat ${1}/etc/rc


echo Generaing a manual bhyve launch script just to be safe

cat << EOF > ${1}/manual-launch.sh
[ -e /dev/vmm/jailhyve ] && \
	{ bhyvectl --destroy --vm=jailhyve ; sleep 2 ; }

bhyve -c 1 -m 1024 -A -H -P \\
        -s 0,hostbridge \\
        -s 31,lpc \\
        -l com1,stdio \\
        -s 2,virtio-blk,jailhyve.raw \\
        -s 3,virtio-net,tap0 \\
        -l bootrom,/usr/local/share/uefi-firmware/BHYVE_UEFI.fd \\
        -s 30:0,fbuf,tcp=0.0.0.0:5900,w=640,h=480,wait \\
        -s 30:1,xhci,tablet \\
        jailhyve
EOF

echo Generating the exec.stop script
cat << EOF > ${1}/etc/rc.shutdown
#!/bin/sh
# exec.stop = "/bin/sh /etc/rc.shutdown jail";
pkill bhyve
sleep 5
# Insert fancy waiting and testing games

[ -e /dev/vmm/jailhyve ] && bhyvectl --destroy --vm=jailhyve
# Fancy waiting games
# Insert fancy termination
[ -e /dev/vmm/jailhyve ] && echo /dev/vmm/jailhyve failed to destroy

exit 0
EOF

#cat ${1}/etc/rc.shutdown

echo Gengerating the exec.poststop script
cat << EOF > ${1}/exec.poststop
#!/bin/sh
echo Destroying VM if present
[ -e /dev/vmm/jailhyve ] && bhyvectl --destroy --vm=jailhyve
[ -e /dev/vmm/jailhyve ] && echo VM failed to destroy

# Probably unmount some devfses

echo Deleting devfs ruleset 100
devfs rule -s 100 delset

echo Destroying tap0 and bridge0
ifconfig tap0 destroy
ifconfig bridge0 destroy

ifconfig

exit 0
EOF

#cat ${1}/exec.poststop


#[ $( which tree ) ] && tree $1

if ! [ -f "$1/jailhyve.raw" ] ; then
	echo ; echo ALERT! ; echo
	echo You need a VM disk image at $1/jailhyve.raw
fi

echo ; echo Generating the launch-jailed-vm.sh script ; echo
cat << EOF > ${1}/launch-jailed-vm.sh
#!/bin/sh
jail -r jailhyve ; jail -c -f $1/jail.conf jailhyve || \\
	{ echo Jail failed to launch ; exit 1 ; }

jls
echo
echo You can connect to the VM with:
echo "cu -l /dev/nmdm1B"
EOF

echo
exit 0
