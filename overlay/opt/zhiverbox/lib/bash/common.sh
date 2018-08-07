#!/bin/bash

# if ZHIVER_LOG is empty or not set, set it to default
[[ -z ${ZHIVER_LOG+x} ]] && ZHIVER_LOG=/var/log/zhiverbox.log
[[ ! -w $ZHIVER_LOG ]] && ZHIVER_LOG=~/zhiverbox.log

# make sure log directory exists
mkdir -p $(dirname $ZHIVER_LOG)

# user input prefix
UINPRFX=">"

# sed intendation
SED_INTEND="          " # 10 spaces
# sed formatting colors
SED_RED='\\033[0;31m'
SED_MAGENTA='\\033[0;35m'
SED_GREEN='\\033[0;32m'
SED_BGREEN='\\033[1;32m'
SED_NC='\\033[0m' # No Color

# bash colors
BOLD='\e[1m'
RED='\e[0;31m'
GREEN='\e[0;32m'
MAGENTA='\e[0;35m'
ORANGE='\e[0;33m'
NC='\x1B[0m'

# zHIVErbox parent directory for mounting btrfs root volumes (subvolid=0)
MOUNT_BTRFSROOT=/run/.btrfsroot

ZHIVERBOX_IPFS_REPO=/etc/zhiverbox/ipfs.repo

display_alert()
#--------------------------------------------------------------------------------------------------------------------------------
# Let's have unique way of displaying alerts
#--------------------------------------------------------------------------------------------------------------------------------
{
	# log function parameters to install.log
	echo "Displaying message: $@" >> $ZHIVER_LOG

	local tmp=""
	[[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"
	
	local indent="         "

	case $3 in
		err)
		echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
		;;

		wrn)
		echo -e "[\e[0;35m warn  \x1B[0m] $1 $tmp"
		;;

		ext)
		echo -e "[\e[0;32m o.k.  \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
		;;

		info)
		echo -e "[\e[0;32m o.k.  \x1B[0m] $1 $tmp"
		;;
		
		todo)
		echo -e "[\e[0;45m TODO  \x1B[0m] $1 $tmp"
		;;
		
		indent)
		echo -e "$indent $1 $tmp"
		;;

		*)
		echo -e "[\e[0;32m ..... \x1B[0m] $1 $tmp"
		;;
	esac
}

write_log()
{
    local ts=$(date +"%Y-%m-%d %T")
    local msg
    case $3 in
		err)
		msg="[ ERROR ] $1 "
		;;

		wrn)
		msg="[ WARN  ] $1 "
		;;

		info)
		msg="[ INFO  ] $1 "
		;;

		*)
		msg="[ ....  ] $1 "
		;;
	esac
	
	echo "$ts $msg" >> $ZHIVER_LOG
}

press_any_key()
{
    read -n 1 -s -r -p "$UINPRFX Press any key to continue."
    printf '\r'
}

new_screen()
{
    echo "" && clear
}

# should be called with eval in a sourcing script
# eval $(assert_interactive)
assert_interactive()
{
	if [ "$-" != "${-#*i}" ]; then
		# continue
		echo -n ""
	else
		#silently exit
		echo -n "return 0"
	fi
}

# should be called with eval in a sourcing script
# eval $(assert_hard_disk_mounted /dev/sda1)
assert_hard_disk_mounted()
{
	DISK=$1
	local disk_mounts=$(lsblk -n -o MOUNTPOINT $DISK | tr -d " \t\n\r")
    
    # silently exit if disk is not mounted
    [[ -z $disk_mounts ]] && echo -n "return 0"
}

# base58 encoding from https://github.com/grondilu/bitcoin-bash-tools/blob/master/bitcoin.sh
declare -a base58=(
      1 2 3 4 5 6 7 8 9
    A B C D E F G H   J K L M N   P Q R S T U V W X Y Z
    a b c d e f g h i j k   m n o p q r s t u v w x y z
)
unset dcr; for i in {0..57}; do dcr+="${i}s${base58[i]}"; done

encodeBase58() 
{
	#[[ -z $base58 ]] declare_base58
	echo -n "$1" | sed -e's/^\(\(00\)*\).*/\1/' -e's/00/1/g' | tr -d '\n'
	dc -e "16i ${1^^} [3A ~r d0<x]dsxx +f" |
	while read -r n; do echo -n "${base58[n]}"; done
}

generatePass20()
{
    # create a 20 character long random passphrase
    TMP_PASS=$(mktemp -p /dev/shm)
    local rand=$(dd if=/dev/urandom bs=4096 count=1 2>/dev/null | sha512sum | awk '{ print $1 }')
    encodeBase58 $rand | cut -c1-20 | tr -d " \t\n\r" > $TMP_PASS
}

get_local_ipv4_addr()
{
	echo $(ip route get 1 | awk '{print $NF;exit}')
}

get_local_cjdns_addr()
{
    echo $(ip add | grep "inet6 fc" | awk '{ print $2 }' | sed 's/\/8//')
}

get_local_ssh_onion_addr()
{
    echo $(cat /var/lib/tor/ssh_hidden_service/hostname)
}

# compare dot separated version strings
# http://ask.xmodulo.com/compare-two-version-numbers.html
function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
