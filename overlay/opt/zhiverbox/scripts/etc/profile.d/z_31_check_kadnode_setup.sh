#!/bin/bash
export ZHIVERBOX_HOME=/opt/zhiverbox
# profile.d scripts are sourced, so DONT'T use exit but return instead

. $ZHIVERBOX_HOME/lib/bash/common.sh

# only do this for interactive shells
eval $(assert_interactive)

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_kadnode_setup

user_abort()
{
    trap '' RETURN
    echo
    display_alert "KadNode setup aborted!" "" "wrn"
    display_alert "You can setup KadNode later. We'll ask you on next login again." "" ""
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
    display_alert "Opting out of KadNode setup. We'll never remind you again. :" "sudo touch $NO_REMIND_SETUP_FILE" "info"
    echo "Admin privileges (sudo) required."
    sudo mkdir -p $(dirname $NO_REMIND_SETUP_FILE)
    sudo touch $NO_REMIND_SETUP_FILE
}

# main script

# if kadnode is not available, silently return
if systemctl status kadnode.service | grep -q 'could not be found'; then
    return
fi

# if user opted out of setup reminder, silently return
[[ -f $NO_REMIND_SETUP_FILE ]] && return

display_alert "Setup peer-to-peer DNS alternative" "KadNode" "todo"
echo -e \
"If you don't have a static Internet IP address but want other users to be able 
to peer/mesh with you (inbound connections) over the Internet (e.g. via Cjdns), 
you need something like DynDNS. However, DynDNS usually means a single service 
provider on top of the centralized DNS system. ${BOLD}zHIVErbox${NC} has a decentralized 
alternative: ${GREEN}KadNode${NC} - which utilizes the BitTorrent P2P network to resolve ${GREEN}.p2p${NC} 
addresses via the Kademlia DHT (Distributed Hash Table).

Options:
1) Setup : Enable and configure KadNode service now.
2) Opt out : I'll handle it by myself. Please don't ask me again!
3) Postpone: Do not setup KadNode right now but remind me later again!"

done=0
while : ; do
	read -p "$UINPRFX Select number: " choice
	case $choice in
		1)  # from now on any RETURN sigs should be traped
			trap user_abort RETURN;
			trap ctrl_c SIGINT;
			
			# run the installer
			bash $ZHIVERBOX_HOME/scripts/install/31_setup-kadnode.sh && SUCCESS=true;
			
			# undo traps
			trap - RETURN
			trap - SIGINT
			break;;
		2) 	opt_out && SUCCESS=true;
			break;;
		3) 	break;;
	esac
done

[[ ! $SUCCESS = true ]] && user_abort
