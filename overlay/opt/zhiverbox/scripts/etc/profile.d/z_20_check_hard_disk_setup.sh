#!/bin/bash

# profile.d scripts are sourced, so DONT'T use exit but return instead

. /opt/zhiverbox/lib/bash/common.sh

# only do this for interactive shells
assert_interactive

# define which hard drive and partition to be checked
DISK=/dev/sda

NO_WARN_MISSING_FILE=/etc/zhiverbox/.no_warn_hard_disk_missing
NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_hard_disk_setup

user_abort()
{
    trap '' RETURN
    echo
    display_alert "Hard disk setup aborted!" "$DISK" "wrn"
    display_alert "You can setup the hard disk later. We'll ask you on next login again." "" ""
    echo
}

ctrl_c()
{   
    trap '' SIGINT
    echo
    echo -n "Aborted. Press RETURN..."
    return
}

check_disk()
{
    if [[ -b $DISK ]]; then
        DISK_DETECTED=true
    fi
}

check_disk_is_mounted()
{
    local disk_mounts=$(lsblk -n -o MOUNTPOINT $DISK | tr -d " \t\n\r")
    if [[ ! -z $disk_mounts ]]; then
        DISK_MOUNTED=true
    fi
}

# main script

check_disk
if [[ ! $DISK_DETECTED ]]; then
    NO_WARN_MISSING_FILE=/etc/zhiverbox/.no_warn_hard_disk_missing
    if [[ ! -f $NO_WARN_MISSING_FILE ]]; then
        # display a warning
        display_alert "No hard disk connected (yet?)!" "$DISK is missing" "wrn"
        display_alert "> To disable this warning permanently run:" "touch $NO_WARN_MISSING_FILE" "indent"
    fi
    return
fi

# if user opted out of setup reminder, silently return
[[ -f $NO_REMIND_SETUP_FILE ]] && return

# if disk is already mounted silently return
check_disk_is_mounted
[[ $DISK_MOUNTED ]] && return

# from now on any RETURN sigs should be traped
trap user_abort RETURN
trap ctrl_c SIGINT

# partition is not mounted
display_alert "SATA hard disk detected but not setup yet!" "$DISK" "todo"
read -p "$UINPRFX Do you want to setup and use this disk now (y/n)? " choice
case "$choice" in 
  y|Y|yes|YES ) bash /opt/zhiverbox/scripts/setup_hard_disk.sh $DISK && SUCCESS=true;;
  * ) return;;
esac

# undo traps
trap - RETURN
trap - SIGINT

[[ ! $SUCCESS ]] && user_abort
