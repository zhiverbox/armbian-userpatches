#!/bin/bash

# arguments: $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP
#
# This is the image customization script

# NOTE: It is copied to /tmp directory inside the image
# and executed there inside chroot environment
# so don't reference any files that are not already installed

# NOTE: If you want to transfer files between chroot and host
# userpatches/overlay directory on host is bind-mounted to /tmp/overlay in chroot

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

Main() {
	case $RELEASE in
		jessie)
			# your code here
			;;
		xenial)
			# your code here
			;;
		stretch)
			# your code here
			Install_zHIVErbox
			;;
		bionic)
			# your code here
			;;
	esac
} # Main

Install_zHIVErbox() {

    # load zhiverbox helpers
    if [[ -f /tmp/overlay/build/helpers.sh ]]; then
		source /tmp/overlay/build/helpers.sh
    else
	    echo "Error: missing build directory structure"
	    echo "Please clone the full repository https://github.com/zhiverbox/armbian-userpatches.git"
	    exit -1
    fi
    
    display_alert "#####################################" "" ""
    display_alert "  Image customization for zHIVErbox    " ""
    display_alert "#####################################" "" ""
    
    # copy /etc/profile for boot system
    copy_initramfs_etc_profile
    
    # zhiverbox hooks for initramfs
	copy_initramfs_tools
    
    # generate motd file for boot system
    debug_make_initramfs_motd
	
	# set the hostname of the zhiverbox in the real rootfs
	# use -insecure suffix to hint user that image hasn't been customized/re-encrypted yet
	echo -n "zhiverbox-insecure" > /etc/hostname
	
	# use a persistent cache for apt packages across builds
	mkdir -p /tmp/cache/apt
	mkdir -p /var/cache/apt
    mount -o bind,rw /tmp/cache/apt /var/cache/apt
	
	# install TOR
	install_tor
	torify_wget
	torify_git
	torify_non_socks
	install_tor_grater
	setup_tor_enforcement_dns
	setup_tor_enforcement_ferm
	
	# setup Tails(Tor) based time syncing using
	setup_time_sync
	
	# zHIVErbox additional security hardening
	security_hardening

	# Special treatment for ODROID-XU4 (and later Amlogic S912, RK3399 and other big.LITTLE
	# based devices). 
	if [ "${BOARD}" = "odroidxu4" ]; then
		# Move typical p2p/dapp daemons to the big cores
		BIG_CORES="4-7"
		BIG_DAEMONS="bitmessage|bitcoind|ipfs|tahoe"
		echo "* * * * * root for i in \`pgrep \"$BIG_DAEMONS\"\` ; do ionice -c1 -p \$i ; taskset -a -c -p $BIG_CORES \$i; done >/dev/null 2>&1" \
			>/etc/cron.d/make_dapp_processes_faster
		chmod 600 /etc/cron.d/make_dapp_processes_faster
	
		# Move typical system daemons to the LITTLE cores
		LITTLE_CORES="0-3"
		LITTLE_DAEMONS="systemd|rsyslogd|polkitd|ntpd|haveged|dbus-daemon|NetworkManager"
		echo "* * * * * root for i in \`pgrep \"$LITTLE_DAEMONS\"\` ; do taskset -a -c -p $LITTLE_CORES \$i; done >/dev/null 2>&1" \
			>>/etc/cron.d/make_dapp_processes_faster
			
		# Move typical user processes to the LITTLE cores, but without the -a option for child processes
		#LITTLE_APPS="sshd|agetty|screen"
		#echo "* * * * * root for i in \`pgrep \"$LITTLE_APPS\"\` ; do taskset -c -p $LITTLE_CORES \$i; done >/dev/null 2>&1" \
		#	>>/etc/cron.d/make_dapp_processes_faster
	fi
	
	# enable save hard disk parking on shutdown
	safe_hard_disk_parking_on_shutdown

	# Update smartmontools drive database, since the Odroid HC1 and HC2 use a SATA disk
	apt-get -y -q install smartmontools
	FILE=$(mktemp)
	wget https://raw.githubusercontent.com/mirror/smartmontools/master/drivedb.h -qO $FILE
	grep -q 'drivedb.h' $FILE && mv $FILE /var/lib/smartmontools/drivedb/drivedb.h && \
		chmod 644 /var/lib/smartmontools/drivedb/drivedb.h
	
	# install secure-delete
    apt-get -y -q install secure-delete
    
    # install btrfs-snp
    install_btrfs_snp
    
    # install cjdns
    install_cjdns
    
    # install kadnode
    build_install_kadnode_from_sources
    
    #
    install_zhiverbox_scripts
    
    # post user setup customization
    install_post_user_setup_customization
    
    # hard disk setup assistance
    install_disk_setup_assistance
    
    # KadNode setup assitance
    install_kadnode_setup_assistance
    
    # IPFS setup assistance
    install_ipfs_setup_assistance
    
    # bitcoind setup assistance
    install_bitcoind_setup_assistance
    
    # motd changes
    motd_change_10_header
    motd_change_30_sysinfo
    motd_add_31_dnets
    motd_change_35_tips
    motd_add_36_donations
    
    # update command not found database
    /usr/sbin/update-command-not-found
    
    # unmount apt cache
    umount /var/cache/apt
	
} # Install_zHIVErbox

Main "$@"
