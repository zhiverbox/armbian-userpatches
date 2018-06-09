#!/bin/bash
export ZHIVERBOX_HOME=/opt/zhiverbox
# profile.d scripts are sourced, so DONT'T use exit but return instead

. $ZHIVERBOX_HOME/lib/bash/common.sh

# only do this for interactive shells
eval $(assert_interactive)

# only do this when hard disk is mounted
eval $(assert_hard_disk_mounted /dev/sda1)

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_bitcoind_setup

user_abort()
{
    trap '' RETURN
    echo
    display_alert "Bitcoin Core setup aborted!" "" "wrn"
    display_alert "You can setup the Bicoin deamon later. We'll ask you on next login again." "" ""
    echo
}

ctrl_c()
{   
    trap '' SIGINT
    echo
    echo -n "Aborted. Press RETURN..."
    return
}

opt_out()
{
    display_alert "Opting out of bitcoind setup. We'll never remind you again. :" "sudo touch $NO_REMIND_SETUP_FILE" "info"
    echo "Admin privileges (sudo) required."
    sudo mkdir -p $(dirname $NO_REMIND_SETUP_FILE)
    sudo touch $NO_REMIND_SETUP_FILE
    return
}

# main script

# if bitcoin is already setup as a system service, silently return
[[ -n $(systemctl status bitcoind.service) || -n $(systemctl status test_bitcoind.service) ]] && return

# if user opted out of setup reminder, silently return
[[ -f $NO_REMIND_SETUP_FILE ]] && return

display_alert "Intstall Bitcoin Core daemon!" "" "todo"
echo -e \
"Bitcoin Core daemon is optional and might not be required on every zHIVErbox.

Options:
1) Install : Install bitcoind now.
2) Opt out : I'll handle it by myself. Please don't ask me again!
3) Postpone: Do not install bitcoind right now but remind me later again!"

done=0
while : ; do
	read -p "$UINPRFX Select number: " choice
	case $choice in
		1)  # from now on any RETURN sigs should be traped
			trap user_abort RETURN;
			trap ctrl_c SIGINT;
			
			bash $ZHIVERBOX_HOME/scripts/install/50_install-bitcoind.sh && SUCCESS=true;
			
			# undo traps
			trap - RETURN
			trap - SIGINT
			break;;
		2) 	opt_out && SUCCESS=true;
			break;;
		3) 	SUCCESS=false;
		    break;;
	esac
done

if [[ $SUCCESS ]]; then

	# dont' ask to install again on next login
	sudo touch $NO_REMIND_SETUP_FILE

	# reload the shell with the new group meberships (requires password)
	display_alert "Re-login as '$USER' to apply new group memberships" "su -l $USER" ""
	su -l $USER
	
	# refresh the group memberships without login (creates two more netsted subshells)
	#newgrp -
	#newgrp $USER
	
else
    user_abort
fi
