#!/bin/bash
export ZHIVERBOX_HOME=/opt/zhiverbox
# profile.d scripts are sourced, so DONT'T use exit but return instead

. $ZHIVERBOX_HOME/lib/bash/common.sh

# only do this for interactive shells
eval $(assert_interactive)

# only do this when hard disk is mounted
eval $(assert_hard_disk_mounted /dev/sda1)

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_ipfs_setup

user_abort()
{
    trap '' RETURN
    echo
    display_alert "IPFS setup aborted!" "" "wrn"
    display_alert "You can setup the IPFS later. We'll ask you on next login again." "" ""
    echo
}

ctrl_c()
{   
    trap '' SIGINT
    echo
    echo -n "Aborted. Press RETURN..."
}

opt_out()
{
    display_alert "Opting out of IPFS setup. We'll never remind you again. :" "sudo touch $NO_REMIND_SETUP_FILE" "info"
    echo "Admin privileges (sudo) required."
    sudo mkdir -p $(dirname $NO_REMIND_SETUP_FILE)
    sudo touch $NO_REMIND_SETUP_FILE
}

# main script

# if IPFS is already setup as a system service, silently return
[[ -n $(systemctl status ipfsd.service 2>/dev/null) || -n $(ipfs id 2>/dev/null) ]] && return

# if user opted out of setup reminder, silently return
[[ -f $NO_REMIND_SETUP_FILE ]] && return

display_alert "SATA hard disk is mounted but IPFS is not setup yet!" "" "todo"
echo -e \
"The zHIVErbox software tools are not hosted on centralized servers, but rely on
IPFS (InterPlanetary File System) instead, which is a distributed public cloud. 
To receive further updates and new tools as they are released, you should setup
IPFS on this zHIVErbox.

Options:
1) Install : Install IPFS now.
2) Opt out : I'll handle it by myself. Please don't ask me again!
3) Postpone: Do not install IPFS right now but remind me later again!"

done=0
while : ; do
	read -p "$UINPRFX Select number: " choice
	case $choice in
		1)  # from now on any RETURN sigs should be traped
			trap user_abort RETURN;
			trap ctrl_c SIGINT;
			
			# run the installer
			bash $ZHIVERBOX_HOME/scripts/install/30_install-ipfs.sh && SUCCESS=true;
			
			# undo traps
			trap - RETURN
			trap - SIGINT
			break;;
		2) 	opt_out && SUCCESS=true;
			break;;
		3) 	break;;
	esac
done

if [[ $SUCCESS = true ]]; then

	# reload the shell with the new group meberships (requires password)
	display_alert "Re-login as '$USER' to apply new group memberships" "su -l $USER" ""
	su -l $USER
	
	# refresh the group memberships without login (creates two more netsted subshells)
	#newgrp -
	#newgrp $USER
	
else
    user_abort
fi
