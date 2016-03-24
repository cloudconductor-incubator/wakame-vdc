#!/bin/bash

# don't run unless $KILLPGOK is set or this script is the process leader
[ -n "$KILLPGOK" ] ||  kill -0 -$$ || {
	echo "((Read the first part of this script to understand its error handling))" 1>&2
	exit 255
    }

export KILLPGOK=yes  # allow for all scripts called by this script to be killed on error

reportfail()
{
    # The goal is to make this function simply (i.e. always) terminate
    # not only this script but also *all* related scripts and
    # processes.  A simple "exit" can be hidden by subprocesses,
    # therefore this function sends SIGTERM to all processes in the
    # same process group as the process that caught the error.  If the
    # process calling this script wants to receive SIGTERM, it should
    # set $KILLPGOK to "yes".  If not, it should call this script with
    # setsid.  Similarly, this script can also use setsid to protect
    # processes that it starts from termination when it makes sense.
    echo "Failed...terminating process group. ($*)" 1>&2
    kill -TERM 0  # see man kill(2), should kill all processes in same process group

    echo "This line should not be reached." 1>&2 ; exit 255
}

evalcheck() { eval "$@" || reportfail "$@,rc=$?" ; }

trap 'echo "pid=$BASHPID exiting" 1>&2 ; exit 255' TERM  # feel free to specialize this

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfail

usage() {
    cat <<'EOF'
(NOTE: this documentation is out-of-date.)

A quick guide for using this script to make Windows images is in
README.md.  This script also has other features for experimenting with
Windows images.  In order to use these, it is probably necessary read
through it to understand the script and its limitations.  However, for
quick hints, the intended use is as follows:

1) Follow instruction in README.md
2) keep calling $SDIR/build-w-answerfile-floppy.sh 2008 -next

This will cycle the window image through first boot, second boot,
shutdown, reboot, sysprep, shutdown, and then start again with first
boot, etc.  At various points, the script will output Windows log
files and network packet dumps to a special build directory. (The scripts
use the path stored in $bdir_fullpath as the build directory.)  The
first set of log files have "gen0" in the log file names.  After the
next first boot, "gen1" becomes part of the log file names, etc., so
that each cycle from first-boot to sysprep gets uniquely named files.
It is easer to make sense of all the log files if the directory is
sorted by date.

Note the following environment are used:
BOOTDATE (defaults to 2014-04-01)  (do BOOTDATE=now for current time and date)
MACADDR (defaults to 52-54-00-11-a0-5b)
FIRSTBOOT (defaults to "", i.e. do not put in meta-data/first-boot)
AUTOACTIVATE (defaults to "", i.e. do not put in directory meta-data/auto-activate)
NATNET (defaults to "", i.e. disconnect from Internet)
PROXY (defaults to "", i.e. do not put in meta-data/auto-activate/auto-activate-proxy)
IPV4 (defaults to 10.0.2.15)
NETMASK (defaults to 255.255.255.0)
GATEWAY (defaults to 10.0.2.2)
IMAGESIZE (defaults to "30G", the parameter suitable for use with qemu-img)
ISO2008 (defaults to "", it must be set before installing Windows Server 2008 R2)
ISO2012 (defaults to "", it must be set before installing Windows Server 2012 R2)

POWERCAT (defaults to "", i.e. do not put a copy of powercat.ps1 in metadata drive for debugging)
EOF
    exit
}

set-environment-var-defaults()
{
    if [ "$BOOTDATE" == "" ] ; then
	# By default, set the date to something later than the files in
	# the Windows Server 2012 ISO.  All the files in the ISO seem to
	# be dated after 2014-03-18.  Setting after this but earlier than
	# today's date makes it possible to do experiments with KVM faking
	# dates but still be using dates that would be plausible to
	# Windows and Microsoft's activation server.
	BOOTDATE="2014-04-01"
    fi

    [ "$MACADDR" == "" ] &&  MACADDR="52-54-00-11-a0-5b"
    [ "$IPV4" == "" ] &&  IPV4="10.0.2.15"
    [ "$NETMASK" == "" ] &&  NETMASK="255.255.255.0"
    [ "$GATEWAY" == "" ] &&  GATEWAY="10.0.2.2"
    [ "$IMAGESIZE" == "" ] &&  IMAGESIZE="30G"

    [ "$KVM_BINARY" == "" ] && KVM_BINARY=qemu-system-x86_64
    [ "$POWERCAT" == "" ] && POWERCAT=true

    source "$SCRIPT_DIR/windows-image-build.ini"

    # Decide on ports for KVM's user-mode networking port forwarding
    RDP=1${UD}389
    SSH=1${UD}022
    MISC=1${UD}123

    # And other ports to be used by KVM
    MONITOR=1${UD}302
    VNC=1${UD}0

    portforward=""
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$RDP-:3389"  # RDP
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$SSH-:22"  # ssh (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:$MISC-:7890"  # test (for testing)
    portforward="$portforward,hostfwd=tcp:0.0.0.0:10050-:10050"  # zabbix
    portforward="$portforward,hostfwd=tcp:0.0.0.0:10051-:10051"  # zabbix

    scriptArray=(
	wakame-init-first-boot.ps1
	sysprep-for-backup.cmd
	SetupComplete-firstboot.cmd
	SetupComplete-install.cmd
	wakame-init-every-boot.cmd
	wakame-init-every-boot.ps1
	wakame-functions.ps1
    )

    VIRTIOISO="virtio-win-0.1-74.iso"  # version of virtio disk and network drivers known to work
    ZABBIXEXE="zabbix_agent-1.8.15-1.JP_installer.exe"
}

boot-date-param()
{
    [ "$BOOTDATE" != "now" ] && echo "-rtc base=$BOOTDATE"
}

boot-common-params()
{
    echo -m 2000 -smp 2 -enable-kvm \
	 -no-kvm-pit-reinjection \
	 -monitor telnet::$MONITOR,server,nowait \
	 -vnc :$VNC \
	 -drive file="$WINIMG",id=windows-drive,cache=none,aio=native,if=none \
	 -device virtio-blk-pci,drive=windows-drive,bootindex=0,bus=pci.0,addr=0x4 \
	 -usbdevice tablet  \
	 -k ja $(boot-date-param)
}

create-metadata-disk()
{
    (
	set -e
	cd "$SCRIPT_DIR"
	rm -f metadata.img
	/usr/bin/truncate -s 10m metadata.img
	parted metadata.img <<EOF
mklabel msdos
mkpart primary fat32 1 10m
quit
EOF
	loopdev="$(mount-partition metadata.img 1 --sudo)"
	sudo mkfs -t vfat -n METADATA "$loopdev"
	umount-partition metadata.img --sudo
	tar czvf empty-metadata.img.tar.gz metadata.img
	rm -f metadata.img
    ) || reportfail "problem while creating metadata.img.tar.gz"
}

configure-metadata-disk()
{
    if ! [ -f metadata.img ]; then
	[ -f "$SCRIPT_DIR/empty-metadata.img.tar.gz" ] || create-metadata-disk
	tar xzvf "$SCRIPT_DIR/empty-metadata.img.tar.gz"
    fi

    [ -f metadata.img ] || reportfail "metadata.img file not found in current directory"
    mount-image metadata.img 1 || reportfail "mounting of metadata.img failed"

    # just enough directories for Windows testing
    sudo bash -c "mkdir -p mntpoint/meta-data/extra-hosts"
    sudo bash -c "mkdir -p mntpoint/meta-data/network/interfaces/macs"
    sudo bash -c "mkdir -p mntpoint/meta-data/public-keys/0"
    sudo bash -c "mkdir -p mntpoint/meta-data/x-monitoring"

    # hostname
    sudo bash -c 'echo "DEMO1-VM" >mntpoint/meta-data/local-hostname'

    # public key
    if ! [ -f testsshkey ]; then
	evalcheck 'ssh-keygen -f testsshkey -N ""'
    fi
    sudo bash -c "mkdir -p mntpoint/meta-data/public-keys/0"
    sudo bash -c "echo $(cat testsshkey.pub) >mntpoint/meta-data/public-keys/0/openssh-key"

    # networking interfaces
    sudo bash -c "mkdir mntpoint/meta-data/network/interfaces/macs/$MACADDR"
    sudo bash -c "echo $IPV4 >mntpoint/meta-data/network/interfaces/macs/$MACADDR/local-ipv4s"
    sudo bash -c "echo $NETMASK >mntpoint/meta-data/network/interfaces/macs/$MACADDR/x-netmask"
    sudo bash -c "echo $GATEWAY >mntpoint/meta-data/network/interfaces/macs/$MACADDR/x-gateway"
    sudo bash -c "echo 8.8.8.8 >mntpoint/meta-data/network/interfaces/macs/$MACADDR/x-dns"
    
    # hosts file
    sudo bash -c 'mkdir mntpoint/meta-data/extra-hosts'
    sudo bash -c 'echo 192.168.2.22 >mntpoint/meta-data/extra-hosts/twotwo'
    sudo bash -c 'echo 192.168.2.23 >mntpoint/meta-data/extra-hosts/twothree'

    # defaults values for zabbix testing
    sudo bash -c "echo $IPV4 >mntpoint/meta-data/local-ipv4"
    sudo bash -c 'echo "DEMO1-VM" >mntpoint/meta-data/instance-id'
    sudo bash -c 'echo "192.168.2.1" >mntpoint/meta-data/x-monitoring/zabbix-servers'
    
    if [ "$FIRSTBOOT" = "" ]; then
	sudo rm -f mntpoint/meta-data/first-boot
    else
	sudo touch mntpoint/meta-data/first-boot
	sudo touch "./first-boot-set-$(date +%y%m%d-%H%M%S)"
    fi

    if [ "$AUTOACTIVATE" = "" ]; then
	sudo rm -fr mntpoint/meta-data/auto-activate
    else
	sudo mkdir -p  mntpoint/meta-data/auto-activate
	sudo touch "./auto-activate-set-$(date +%y%m%d-%H%M%S)"
    fi

    if [ "$PROXY" = "" ]; then
	sudo rm -f mntpoint/meta-data/auto-activate/auto-activate-proxy
    else
	echo "$PROXY" | sudo tee mntpoint/meta-data/auto-activate/auto-activate-proxy
	sudo touch "./auto-activate-proxy-set-$(date +%y%m%d-%H%M%S)"
    fi

    POWERCAT_URL="https://raw.githubusercontent.com/besimorhino/powercat/master/powercat.ps1"
    POWERCAT_LOCAL="$SCRIPT_DIR/powercat.ps1"
    # For reference, powercat.ps1 from commit 081bd91 has worked well.
    

    if [ "$POWERCAT" != "" ]; then
	if ! [ -f "$POWERCAT_LOCAL" ]; then
	    curl "$POWERCAT_URL" -o "$POWERCAT_LOCAL" || {
		umount-image
		reportfail "Could not download powercat.ps1"
	    }
	fi
	sudo cp "$POWERCAT_LOCAL" mntpoint/powercat.ps1

	sudo bash -c "cat >mntpoint/powercat.hint" <<EOF

Powercat.ps1 gives netcat functionality to PowerShell, but command
options are quite different from netcat in Linux so be sure to read
the help in the file.  One particularly useful option is -ep, which
makes it easy to create a remote shell that can be driven by test
scripts running on a Linux machine.

Before using it is necessary to source the powercat.ps1 file.
Do so by opening up a PowerShell window and doing:
. ./powercat.ps1

(On Windows Server 2008, it may be necessary to do this first:
set-executionpolicy remotesigned
)

Remote shell hint:
==================
On some reachable Linux host do the following in a terminal:
nc -l 6789

Then in the some PowerShell window do:
powercat -c ip.address.of.linux -p 6789 -ep

A PowerShell prompt should appear in the Windows terminal and remote
commands can be issued, with some limitations.  Experiment!

File from Linux hint:
=====================
On some reachable Linux host do the following:
cat source-file | nc -l 6789

Then in the some PowerShell window do:
powercat -c ip.address.of.linux -p 6789 -of c:/full/path/to/target/file
(not sure why relative file paths did not work)

File to Linux hint:
===================
On some reachable Linux host do the following:
nc -l 6789 </dev/null >target_file

Then in the some PowerShell window do:
powercat -c ip.address.of.linux -p 6789 -i c:/full/path/to/source/file
(here a relative path failed, but one in the same directory worked)

Good Luck!
EOF
    fi
    
    umount-image
}

boot-and-log-kvm-boot()
{
    echo "$KVM_BINARY" "$@" >"./kvm-boot-cmdline-$(date +%y%m%d-%H%M%S)"
    "$KVM_BINARY" "$@"  >>./kvm.stdout 2>>./kvm.stderr &
    echo "$!" >./kvm.pid
    # the following are used by kvm-ui-util.sh
    echo "$MONITOR" >./kvm.mon
    echo "$(( VNC + 5900 ))" >./kvm.vnc
}

source "$SCRIPT_DIR/mount-partition.sh" load

mount-image()
{
    imagename="$1"
    partion="$2"
    options="$3"
    
    [ -d mntpoint ] || evalcheck mkdir mntpoint
    mount-partition "$imagename" "$partion" mntpoint $options --sudo
}

umount-image()
{
    umount-partition mntpoint --sudo
}

kill-kvm()
{
    kvmpid="$(< ./kvm.pid)"
    if [ -d /proc/$kvmpid ]; then
	echo "Terminating KVM instance pid=$kvmpid"
	kill -TERM "$kvmpid"
    else
	echo "KVM already stopped."
    fi
}

tar-up-windows-logs()
{
    # potentially interesting logs and directories for debugging
    windowsLogs=(
	Windows/DtcInstall.log
	Windows/inf/setupapi.app.log
	Windows/Panther
	Windows/setupact.log
	Windows/System32/sysprep
	Windows/TSSysprep.log
	Windows/WindowsUpdate.log
	Windows/Setup
	"'Program Files/ZABBIX Agent/zabbix_agentd.conf'"
    )

    target="$1"
    [ -d mntpoint/Windows ] || reportfail "Windows disk image not mounted"
    # eval is needed to deal with the quotes needed for spaces in a file name
    echo "Making tar file of log files from Windows image --> $target"
    eval tar czf "$target" -C mntpoint "${windowsLogs[@]}"
    cp $(pwd)/qemu-vlan0.pcap "${target%.tar.gz}.pcap" 2>/dev/null
}

mount-tar-umount()
{
    partitionNumber=2
    mount-image "$WINIMG" $partitionNumber "-o ro"
    tar-up-windows-logs "$1"
    umount-image
}

confirm-sysprep-shutdown()
{
    [ -d /proc/$(< ./kvm.pid) ] && reportfail "KVM still running"
    return 0
}

install-windows-from-iso()
{
    [ -f "$SCRIPT_DIR/$WINISO" ] || reportfail "Windows install ISO file not found ($WINISO)"
    # Copy Autounattend.xml into fresh floppy image
    FLP="./answerfile-floppy.img"
    dd if=/dev/zero of="$FLP" bs=1k count=1440
    mkfs.vfat "$FLP"
    mkdir -p "./mntpoint"
    sudo mount -t vfat -o loop $FLP "./mntpoint"
    sudo cp "$SCRIPT_DIR/$ANSFILE" "./mntpoint/Autounattend.xml"
    for fn in "${scriptArray[@]}" FinalStepsForInstall.cmd Unattend-for-first-boot.xml $ZABBIXEXE ; do
	sudo cp "$SCRIPT_DIR/$fn" "./mntpoint/"
    done

    # Here we are inserting code that sets the product key
    # at the start of the batch file that runs sysprep.
    # An alternative
    # would have been to set it in the answer file, but we are trying
    # to keep the answer file as simple as possible.  Another
    # alternative seemed to be to use FinalStepsForInstall.cmd, but
    # for some reason that did not work.
    # Also adding the call to the zabbix installer here so that the base
    # version of the run-sysprep.cmd file does not hard code the exact name
    # of the zabbix installer.
    prodkey="$(cat keyfile)" || reportfail "File named \"keyfile\" with MAK product key must be in the current directory"
    {
	echo "A:$ZABBIXEXE"
	echo "cscript //b c:\windows\system32\slmgr.vbs /ipk $prodkey"
	echo
	cat "$SCRIPT_DIR/run-sysprep.cmd" # copy in the rest of the batch file script that runs sysprep
    } | sudo tee ./mntpoint/run-sysprep.cmd

    sudo umount "./mntpoint"
    
    # Create a blank image into which Windows will soon be installed
    rm -f "$WINIMG"
    qemu-img create -f raw "$WINIMG" 30G

    if [ "$NATNET" = "" ] ; then
	# have netdevice connect to mcast, which effectively creates a device not connected to anything
	boot-and-log-kvm-boot $(boot-common-params) \
			      -fda "$FLP" \
			      -drive file="$SCRIPT_DIR/$WINISO",index=2,media=cdrom \
			      -drive file="$SCRIPT_DIR/$VIRTIOISO",index=3,media=cdrom \
			      -boot d \
			      -net nic,vlan=0,macaddr=$MACADDR \
			      -net socket,vlan=0,mcast=230.0.$UD.1:12341
    else
	# use user mode network w/ NAT
	mv qemu-vlan0.pcap "$(date +%y%m%d-%H%M%S)"-qemu-vlan0.pcap
	boot-and-log-kvm-boot $(boot-common-params) \
			      -fda "$FLP" \
			      -drive file="$SCRIPT_DIR/$WINISO",index=2,media=cdrom \
			      -drive file="$SCRIPT_DIR/$VIRTIOISO",index=3,media=cdrom \
			      -boot d \
			      -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
			      -net dump,vlan=0 \
			      -net user,vlan=0${portforward}
    fi
}

boot-without-networking()
{
    configure-metadata-disk
    mv qemu-vlan0.pcap "$(date +%y%m%d-%H%M%S)"-qemu-vlan0.pcap
    boot-and-log-kvm-boot $(boot-common-params) \
			  -drive file="metadata.img",id=metadata-drive,cache=none,aio=native,if=none \
			  -device virtio-blk-pci,id=metadata,drive=metadata-drive,bus=pci.0,addr=0x5 \
			  -net nic,vlan=0,macaddr=$MACADDR \
			  -net dump,vlan=0 \
			  -net socket,vlan=0,mcast=230.0.$UD.1:12341
}

boot-with-networking()
{
    configure-metadata-disk
    mv qemu-vlan0.pcap "$(date +%y%m%d-%H%M%S)"-qemu-vlan0.pcap
    boot-and-log-kvm-boot $(boot-common-params) \
			  -drive file="metadata.img",id=metadata-drive,cache=none,aio=native,if=none \
			  -device virtio-blk-pci,id=metadata,drive=metadata-drive,bus=pci.0,addr=0x5 \
			  -net nic,vlan=0,model=virtio,macaddr=$MACADDR \
			  -net dump,vlan=0 \
			  -net user,vlan=0${portforward}
}

# from: http://blog.vmsplice.net/2011/04/how-to-capture-vm-network-traffic-using.html
# $ qemu -net nic,model=e1000 -net dump,file=/tmp/vm0.pcap -net user
# $ /usr/sbin/tcpdump -nr /tmp/vm0.pcap

get-decode-password()
{
    mount-image metadata.img 1 "-o ro"
    if [ -f "mntpoint/meta-data/pw.enc" ]
    then
	pwtxt="$(openssl rsautl -decrypt -inkey testsshkey -in mntpoint/meta-data/pw.enc -oaep)"
	echo "$pwtxt"
    elif [ -f "mntpoint/pw.enc" ] # old location, for checking images from older tests
    then
	pwtxt="$(openssl rsautl -decrypt -inkey testsshkey -in mntpoint/pw.enc -oaep)"
	echo "$pwtxt"
    else
	set +x
	echo
	echo "---encrypted file not available yet---"
    fi
    umount-image 2>/dev/null 1>/dev/null
}

final-seed-image-packaging()
{
    # checks, setup
    initialtar="$(echo ./windows-*tar.gz)"
    seedtar="windows${LABEL}r2.x86_64.kvm.md.raw.tar.gz"
    [ -f "$initialtar" ] || reportfail "Initial tar file not found in $(pwd)"
    [ -d final-seed-image ] && reportfail "Seed image already packaged"
    mkdir ./final-seed-image
    (
	evalcheck cd ./final-seed-image
	
	# move clean image into place
	time evalcheck 'tar xzvf ../windows-*tar.gz'
	[ -f "$WINIMG" ] || reportfail "No Windows image found in the tar file"
	evalcheck 'mv "$WINIMG" "${seedtar%.tar.gz}"'
	
	# modify ntfs label
	partitionNumber=1
	loopdev="$(
         # just attaches /loop device, no mounting
         evalcheck mount-partition "${seedtar%.tar.gz}" $partitionNumber --sudo)" 
	udevadm settle # probably not needed

	evalcheck sudo ntfslabel "$loopdev" root
	evalcheck umount-partition "${seedtar%.tar.gz}" --sudo
	
	# package
	set -x # show the user what this step is spending so much time doing
	time evalcheck 'tar czvSf "$seedtar" "${seedtar%.tar.gz}"'
	time evalcheck 'md5sum "$seedtar" >"$seedtar".md5'
    )
}

final-seed-image-qcow()
{
    seedtar="windows${LABEL}r2.x86_64.kvm.md.raw.tar.gz"
    seedraw="windows${LABEL}r2.x86_64.kvm.md.raw"
    seedqcow="windows${LABEL}r2.x86_64.15071.qcow2"
    [ -f "./final-seed-image/$seedqcow" ] && reportfail "Image already converted into qcow2 format"
    [ -f "./final-seed-image/$seedtar" ] || reportfail "Must first run -package to make $seedtar"
    (
	evalcheck cd ./final-seed-image
	pwd
	set -x # show the user what this step is spending so much time doing
	[ -f "$seedraw" ] || tar xzvf "$seedtar"
	evalcheck qemu-img convert -f raw -O qcow2 "$seedraw" "$seedqcow"
	evalcheck md5sum "$seedqcow" >"$seedqcow.md5"
	evalcheck gzip "$seedqcow"
	evalcheck md5sum "$seedqcow.gz" >"$seedqcow.gz.md5"
    )
}

updatescripts-raw()
{
    # Update scripts inside existing Windows image.  The motivation here
    # is to avoid installing the image from scratch to speed up debugging.
    for fn in "${scriptArray[@]}" ; do
	sudo cp "$SCRIPT_DIR/$fn" ./mntpoint/Windows/Setup/Scripts
    done
    cp ./mntpoint/Windows/Setup/Scripts/SetupComplete-firstboot.cmd \
       ./mntpoint/Windows/Setup/Scripts/SetupComplete.cmd
}




parse-initial-params()
{
    # All the commands make use of persistent state that is saved
    # between commands in a special build directory.  A new build
    # directory is created for each experiment or Windows build so
    # that information that could be useful for debugging is
    # preserved.

    # The convention is for the *first* parameter to be the build
    # directory and for the *second* parameter to be the name of the
    # command.  If the command requires additional parameters, these
    # are listed after the command.

    # The reason for this ordering is that experience has shown that
    # the same build directory is often reused for several commands.
    # As first parameter, it is easier to leave it unchanged when
    # recalling and modifying commands in a shell console.

    # All the commands expect the build directory to already exist.
    # The only exception is the "0-init" command, which creates a new
    # build directory.

    # The following code sets up for the above convention and adds a
    # heuristic that should make command-line life easier when
    # transitioning to new build directories.  In some cases, it
    # makes it possible to leave off the first parameter and still
    # have everything work correctly.  All this is simpler to code
    # than explain, so will leave the rest of this comment as a TODO
    # item.

    if [[ "${params[0]//[0-9]/}" == -* ]]; then
	# if no build directories start with a sequence of zero
	# or more numbers followed by a dash, then this must be a command
	thecommand="${params[0]}"
	bd_partialpath="./run-"  # guess dir is in current directory and has prefix run-
	unset params[0]
    else
	thecommand="${params[1]}"
	bd_partialpath="${params[0]}"  # guess dir has the given prefix
	unset params[1]
	unset params[0]
    fi
    params=( "${params[@]}" )  # shift array

    if [[ "$thecommand" = "0-init" ]]; then
	# check here before creating a new directory
	[ "${params[0]}" = 2008 ] || [ "${params[0]}" = 2012 ] || usage
    fi
    
    # if path has explicit slash at the end, skip heuristic stuff below. 
    if [[ "$bd_partialpath" == */ ]]; then
	# Use exactly what the user gives.
	bdir_fullpath="$bd_partialpath"
	if [[ "$thecommand" = "0-init" ]]; then
	    evalcheck 'mkdir "$bdir_fullpath"'
	fi
	bdir_fullpath="$(cd "$bdir_fullpath" && pwd)"
	return 0 # skip heuristic
    fi
	    
    # the heuristic stuff
    if [[ "$thecommand" = "0-init" ]]; then
	# extend prefix until it is a unique, new directory
	firstparam="${params[0]}"  # assume 2008 or 2012
	ccc=0
	while bdir_fullpath="$bd_partialpath$firstparam-$(printf "%04d" $ccc)" && \
		[ -d "$bdir_fullpath" ]; do
	    [ "$ccc" -lt 10000 ] || reportfail "Could not generate unique directory path"
	    ccc=$(( ccc + 1 ))
	done
	evalcheck 'mkdir "$bdir_fullpath"'
	bdir_fullpath="$(cd "$bdir_fullpath" && pwd)"
    else
	shopt -s nullglob
	bdir_fullpath=""
	for apath in "$bd_partialpath"*; do  # should already be sorted
	    [ -f "$apath/active" ] && bdir_fullpath="$apath"
	done
	[ "$bdir_fullpath" = "" ] && reportfail "No active build directories found"
	# use the latest that is still active
	bdir_fullpath="$(cd "$bdir_fullpath" && pwd)"
    fi
    # There.  Now the rest of the code should be straightforward, only
    # using $thecommand, $bdir_fullpath, and "${params[@]}"
}

dispatch-command()
{
    if [ "$1" == "-next" ]
    then
	cmd="$(< ./nextstep)"
    else
	cmd="$1"
    fi
    genCount="${cmd#*gen}"
    genCount="${genCount%%-*}"
    instructions="" # instructions to output when step has finished

    case "$cmd" in
	-screendump | -screenshot | -sd | -ss)
	    dumptime="$(date +%y%m%d-%H%M%S)"  # assume not more than one dump per second
	    echo "screendump ./screendump-$dumptime.ppm" | nc localhost $MONITOR
	    ;;
	-mm*) # mount metadata
	    mount-image metadata.img 1
	    ;;
	-mtu) # *m*ount windows image, *t*ar log files, *u*mount
	    [[ "$2" == *tar.gz ]] || reportfail "*.tar.gz file required for 3rd parameter"
            mount-tar-umount "$orgpwd/$2"
	    ;;
	-updatescripts) # push latest scripts into existing untared seed image
	    partitionNumber=2
	    mount-image "$WINIMG" $partitionNumber
	    updatescripts-raw
	    umount-image
	    ;;
	-mountrw)
	    partitionNumber=2
	    mount-image "$WINIMG" $partitionNumber
	    ;;
	-mount)
	    partitionNumber=2
	    mount-image "$WINIMG" $partitionNumber "-o ro"
	    ;;
	-umount)
	    umount-image
	    ;;
	-testoff)
	    boot-without-networking
	    ;;
	-test)
	    boot-with-networking
	    ;;
	-pw)
	    get-decode-password
	    ;;
	-kill*kvm)
	    kill-kvm
	    ;;
	-cleanup)
	    umount-image
	    kill-kvm
	    ;;
	### The commands above are mainly utility commands.  The
	### commands below are the type that go into ./nextstep, that
	### is, those that are used to walk through the build process
	### and the test scenario cycle.
	0-init)
	    : # now handled as a build case
	    ;;
	9999-finalize)
	    echo "Removing the file: $bdir_fullpath/active"
	    rm "$bdir_fullpath/active"
	    ;;
	1-install)
	    install-windows-from-iso
	    echo "1b-record-logs-at-ctr-alt-delete-prompt-gen0" >./nextstep
	    echo "View KVM's display using 'vncviewer :$(cat ./kvm.vnc)'"
	    instructions="$(
 	      echo "Be sure to wait for Windows to finish installing and the 'Ctrl + Alt + Del' screen to appear."
	      echo "Do not log in yet.  First, do -next to record the logs." )"
	    ;;
	1b-record-logs-at-ctr-alt-delete-prompt-gen0)
	    mount-tar-umount ./at-$cmd.tar.gz
	    echo "2-confirm-sysprep-gen0" >./nextstep
	    instructions="$(
	      echo "Login with using the password 'a:run-sysprep'"
	      echo "Then open a PowerShell window by clicking on the blue >_ icon"
	      echo "at the bottom of the screen."
	      echo "Type 'a:run-sysprep' in the PowerShell window to run sysprep"
	      echo "Wait for KVM to shutdown.  Then do -next." )"
	    ;;
	2-confirm-sysprep-gen0)
	    confirm-sysprep-shutdown
	    mount-tar-umount ./after-gen0-sysprep.tar.gz
	    echo "3-tar-the-image" >./nextstep
	    instructions="$(
	      echo "Nothing to wait for on this command.  Do -next to tar the new seed image." )"
	    ;;
	3-tar-the-image)
	    (
		set -x # show the user what this step is spending so much time doing
		time md5sum "$WINIMG" >"$WINIMG".md5
		time tar czSvf "windows-$LABEL-$(cat ./timestamp)".tar.gz "$WINIMG" "$WINIMG".md5
	    )
	    mount-tar-umount ./after-gen0-sysprep.tar.gz
	    echo "4-package-tgz-image" >./nextstep
	    instructions="$(
	      echo "Finished making the tar archive."
	      echo "Do -next to package tar.gz image" )"
	    ;;
	4-package-tgz-image)
	    final-seed-image-packaging
	    echo "5-package-qcow-image" >./nextstep
	    instructions="$(
	      echo "Do -next to package qcow image" )"
	    ;;
	5-package-qcow-image)
	    final-seed-image-qcow
	    echo "1001-gen0-first-boot" >./nextstep
	    instructions="$(
	      echo "Do -next to start testing with first boot" )"
	    ;;
	1001-gen*-first-boot)
	    mount-tar-umount ./before-$cmd.tar.gz
	    [ "$NATNET" = "" ] && boot-without-networking || boot-with-networking
	    echo "1002-confirm-gen$genCount-shutdown-get-pw" >./nextstep
	    instructions="$(
	      echo "Be sure to wait for Windows to boot"
	      echo "and then wait for it to automatically shutdown and KVM to exit."
	      echo "Then, do -next to record the logs and decode the random password" )"
	    ;;
	1002-confirm-gen*-shutdown-get-pw)
	    [ -d /proc/$(< ./kvm.pid) ] && reportfail "KVM still running"
	    mount-tar-umount ./after-$cmd.tar.gz
	    get-decode-password | tee ./pw
	    echo "1003-gen$genCount-second-boot" >./nextstep
	    instructions="$(
	      echo "Nothing to wait for on this command.  Do -next to start the second boot." )"
	    ;;
	1003-gen*-second-boot)
	    evalcheck 'thepid="$(cat ./kvm.pid)"'
	    kill -0 $thepid && reportfail "expecting KVM not to be already running"
	    [ "$NATNET" = "" ] && boot-without-networking || boot-with-networking
	    echo "1003b-record-logs-at-ctr-alt-delete-prompt1-gen$genCount" >./nextstep
	    instructions="$(
	      echo "Be sure to wait for Windows to finish booting and the 'Ctrl + Alt + Del' screen to appear."
	      echo "Do not log in yet.  First, do -next to record the logs." )"
	    ;;
	1003b-record-logs-at-ctr-alt-delete-prompt1-gen*)
	    mount-tar-umount ./at-$cmd.tar.gz
	    echo "1004-confirm-gen$genCount-shutdown" >./nextstep
	    instructions="$(
	      echo "Now log in with the password '$(< ./pw)'"
	      echo "After logging in, manually do a shutdown command and wait for KVM to exit."
	      echo "Then do -next to record the logs and start the third boot." )"
	    ;;
	1004-confirm-gen*-shutdown)
	    [ -d /proc/$(< ./kvm.pid) ] && reportfail "KVM still running"
	    mount-tar-umount ./after-$cmd.tar.gz
	    [ "$NATNET" = "" ] && boot-without-networking || boot-with-networking
	    echo "1004b-record-logs-at-ctr-alt-delete-prompt2-gen$genCount" >./nextstep
	    instructions="$(
	      echo "Be sure to wait for Windows to finish booting and the 'Ctrl + Alt + Del' screen to appear."
	      echo "Do not log in yet.  First, do -next to record the logs." )"
	    ;;
	1004b-record-logs-at-ctr-alt-delete-prompt2-gen*)
	    mount-tar-umount ./at-$cmd.tar.gz
	    echo "1005-confirm-gen$genCount-sysprep-shutdown" >./nextstep
	    instructions="$(
	      echo "Now log in with the (same) password: '$(< ./pw)'"
	      echo "After logging in, open a PowerShell window.  Change the directory"
	      echo "to C:\Windows\Setup\Scripts."
	      echo "Then run the script './sysprep-for-backup.cmd' to run sysprep."
	      echo "Be sure to wait for Windows to automatically shutdown"
	      echo "and then wait for it to automatically shutdown and KVM to exit."
	      echo "Then do -next to record the logs" )"
	    ;;
	1005-confirm-gen*-sysprep-shutdown)
	    confirm-sysprep-shutdown
	    mount-tar-umount ./after-$cmd.tar.gz
	    echo "1001-gen$((genCount + 1))-first-boot" >./nextstep
	    instructions="$(
	      echo "This completes the first cycle of the test scenario."
	      echo "Do -next to start a new test cycle using the newly syspreped image." )"
	    ;;
	*)
	    reportfail "Invalid command for 2nd parameter"
	    ;;
    esac
}

dispatch-init-command()
{
    LABEL="$1"
    LABEL2="${LABEL:2}"  # 08 or 12
    shopt -s nullglob
    [ "$(echo *)" = "" ] || reportfail "Directory to initialize is not empty"

    echo "$LABEL" >./LABEL
    echo "win-$LABEL.raw" >./WINIMG
    echo "Autounattend-$LABEL2.xml" >./ANSFILE
    case "$LABEL" in
	2008)
	    echo "$ISO2008" >./WINISO
	    echo 8 >./active
	    ;;
	2012)
	    echo "$ISO2012" >./WINISO
	    echo 9 >./active
	    ;;
    esac
    cp "$SCRIPT_DIR/key$LABEL" ./keyfile

    echo "1-install" >./nextstep
    echo "$(date +%y%m%d-%H%M%S)" >./timestamp
    echo "This directory will make more sense if you sort by the files by date: ls -lt" >./README

    # The value in active is a single digit used to make port
    # assignment unique.  Currently the script automatically keeps one
    # 2008 experiment/build separate from one 2012
    # experiment/build. There is potential to generalize this more,
    # but for now leaving such generalization as a TODO. As a quick
    # hack, the next code scans to see if any active experiment/builds
    # use the same digit.
    UD="$(< ./active)"
    result="$(cd .. ; grep "$UD" */active)"
    if [[ "$result" == *active*active ]]; then
	echo "WARNING:"
	echo "Two or more active experiment/builds use the same digit"
	echo "for making port assignments unique:"
	echo "$result"
	echo "Consider changing the contents of:"
	echo "$bdir_fullpath/active"
	sleep 2
    fi
}

read-persistent-values()
{
    evalcheck 'LABEL="$(cat ./LABEL)"'
    evalcheck 'WINIMG="$(cat ./WINIMG)"'
    evalcheck 'ANSFILE="$(cat ./ANSFILE)"'
    evalcheck 'WINISO="$(cat ./WINISO)"'
    evalcheck 'UD="$(cat ./active)"'
}

window-image-utils-main()
{
    orgpwd="$(pwd)"
    params=( "$@" )
    parse-initial-params

    # update convenience shortcut
    rm -f lastdir
    ln -s "$bdir_fullpath" lastdir

    echo "Starting build-w-answerfile-floppy.sh ($thecommand)"
    echo "    bdir_fullpath=$bdir_fullpath"
    echo "    \${params[@]}=${params[@]}"
    echo "    ./nextstep=$(cat "$bdir_fullpath/nextstep" 2>/dev/null)"

    evalcheck 'cd "$bdir_fullpath"'
    if [ "$thecommand" = "0-init" ]; then
	dispatch-init-command "${params[@]}"
    else
	read-persistent-values
	set-environment-var-defaults
	dispatch-command "$thecommand" "${params[@]}"
    fi
    echo "Finished build-w-answerfile-floppy.sh ($thecommand), ./nextstep is now $(cat "$bdir_fullpath/nextstep" 2>/dev/null)"
    echo
    echo "$instructions"
    echo
}
window-image-utils-main "$@"
