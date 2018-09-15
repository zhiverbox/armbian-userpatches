#!/bin/bash
export ZHIVERBOX_HOME=/opt/zhiverbox
# profile.d scripts are sourced, so DONT'T use exit but return instead

. $ZHIVERBOX_HOME/lib/bash/common.sh

# only do this for interactive shells
eval $(assert_interactive)

# only do this when bitcoind is already installed as system service
[[ -z $(systemctl status bitcoind.service 2>/dev/null) && -z $(systemctl status test_bitcoind.service 2>/dev/null) ]] && return

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_btc-rpc-explorer_setup

user_abort()
{
    trap '' RETURN
    echo
    display_alert "BTC RPC Explorer setup aborted!" "" "wrn"
    display_alert "You can setup the BTC RPC Explorer later. We'll ask you on next login again." "" ""
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
    display_alert "Opting out of BTC RPC Explorer setup. We'll never remind you again. :" "sudo touch $NO_REMIND_SETUP_FILE" "info"
    echo "Admin privileges (sudo) required."
    sudo mkdir -p $(dirname $NO_REMIND_SETUP_FILE)
    sudo touch $NO_REMIND_SETUP_FILE
}

# main script

# if user opted out of setup reminder, silently return
[[ -f $NO_REMIND_SETUP_FILE ]] && return

display_alert "Intstall BTC RPC Explorer!" "" "todo"
echo -e \
"BTC RPC Explorer is optional and might not be required on every zHIVErbox.
However, BTC RPC Explorer is graphical interface for your Bitcoin fullnode.
It preserves your privacy when exploring the Bitcoin blockchain. E.g. when
looking up Bitcoin account balances and transactions.
Have a look at the live demo here: https://btc.chaintools.io

Options:
1) Install : Install BTC RPC Explorer now.
2) Opt out : I'll handle it by myself. Please don't ask me again!
3) Postpone: Do not install BTC RPC Explorer right now but remind me later
             again!"

done=0
while : ; do
    read -p "$UINPRFX Select number: " choice
    case $choice in
        1)  # from now on any RETURN sigs should be traped
            trap user_abort RETURN;
            trap ctrl_c SIGINT;

            # run the installer
            bash $ZHIVERBOX_HOME/scripts/install/51_install-btc-rpc-explorer.sh && SUCCESS=true;

            # undo traps
            trap - RETURN
            trap - SIGINT
            break;;
        2)     opt_out && return;; # exit this script
        3)     SUCCESS=false; break;;
    esac
done

[[ ! $SUCCESS = true ]] && user_abort
