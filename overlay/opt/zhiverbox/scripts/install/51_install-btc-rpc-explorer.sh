#!/bin/bash

# meta info for list_available_installers.sh
SNAME="zHIVErbox BTC RPC Explorer Installer"
SVERSION="0.1.1"

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_btc-rpc-explorer_setup

[[ -z ${ZHIVERBOX_HOME} ]] && echo "\$ZHIVERBOX_HOME environment variable not set!" && exit 1
. $ZHIVERBOX_HOME/lib/bash/common.sh
. $ZHIVERBOX_HOME/lib/bash/install-helpers.sh

# get the path to this script
SRC=${BASH_SOURCE[0]}

if [[ $EUID != 0 ]]; then
    display_alert "btc-rpc-explorer setup requires admin priviliges, trying to use sudo" "" "wrn"
    sudo -E bash "$SRC" "$@"
    exit $?
fi

SRC_HOME=${1:-/mnt/data}
[[ -z ${SRC_HOME} ]] && echo "\$SRC_HOME argument not set!" && exit 1
mkdir -p $SRC_HOME

# http port of btc-rpc-explorer (see bin/www)
HTTP_PORT=3002

# wrapper script to run btc-rpc-explorer for MAINNET or TESTNET
WRAPPER=$ZHIVERBOX_HOME/scripts/btc-rpc-explorer/btc-rpc-explorer

build_btcrpcexplorer()
{
    # https://github.com/janoside/btc-rpc-explorer/blob/master/README.md

    # make sure node and yarn are setup
    check_install_nodejs

    while [ ! ${BTC_RPC_EXPLORER_CHECKOUT_COMPLETE}  ]
    do
        clone_or_update_from_github "btc-rpc-explorer" "https://github.com/janoside/btc-rpc-explorer" "master"
    done

    display_alert "Building btc-rpc-explorer from sources" "sudo -u user yarn install" ""
    local workdir=$(pwd)
    chown -R user:users $SRC_HOME/btc-rpc-explorer
    cd $SRC_HOME/btc-rpc-explorer
    sudo -u user yarn install
}

install_btcrpcexplorer()
{
    echo ""
    display_alert "Setting up btc-rpc-explorer as on-demand application" "" ""
    echo -e \
"Altough BTC RPC Explorer is a web application, we won't set it up as service
(daemon) on your zHIVErbox. Why? It offers no user authentication and due to
it's powerful built-in RPC functionality it might expose security risks or leak
the privacy of your Bitcoin node if available to everybody. On the other hand it
is a stateless, databaseless application which doesn't need to run all the time.
Therefore we'll start it only when needed by you.
"
    press_any_key

    # install wrapper script
    sed -i "s~^SRC_HOME=.*\$~SRC_HOME=$SRC_HOME/btc-rpc-explorer~" $WRAPPER
    sed -i "s~^HTTP_PORT=.*\$~HTTP_PORT=$HTTP_PORT~" $WRAPPER
    install -o root -g root -m 0755 $WRAPPER /usr/local/bin/$(basename $WRAPPER)
}

configure_firewall()
{
    local fwrulesdir=/etc/ferm/ferm.d
    display_alert "Configuring ferm firewall for btc-rpc-explorer..." "$fwrulesdir/btc-rpc-explorer.*" ""
    mkdir -p $fwrulesdir 2>/dev/null

    # copy all btc-rpc-explorer related firewall rules
    local backupdirname=$(echo "_backups/`date +%s`_btc-rpc-explorer")
    for source in $ZHIVERBOX_HOME/scripts$fwrulesdir/btc-rpc-explorer.*; do
        sfilename=$(basename $source)
        tfilename=${sfilename}
        target=$fwrulesdir/$tfilename
        # strip .src to get the final filename
        rfilename=$(echo "$tfilename" | sed 's~.src$~~')
        rtarget=$fwrulesdir/$rfilename
        if [[ -f $fwrulesdir/$rfilename ]]; then
            # the file already exists from a previous installation
            # create a backup and display a warning
            display_alert "Firewall file already exists:" "$fwrulesdir/$rfilename" "wrn"
            mkdir -p $fwrulesdir/$backupdirname 2>/dev/null
            cp $rtarget $fwrulesdir/$backupdirname/$rfilename.bak
            display_alert "Created backup copy:" "$fwrulesdir/$backupdirname/$rfilename.bak" "ext"
        fi
        # copy the file
        cp $source $target

        # replace the placeholders in the .src files
        if [[ $(basename $target) =~ .src$ ]]; then
            sed -i "s/{{HTTP_PORT}}/${HTTP_PORT}/" $target

            # rename the target to strip the .src extension
            mv $target $(echo "$target" | sed 's~.src$~~')
        fi
    done

    display_alert "Restarting ferm firewall..." "systemctl restart ferm" ""
    systemctl restart ferm
}

show_manual()
{
    echo -e "${BOLD}So how do I start and access BTC RPC Explorer?${NC}"
    press_any_key

    echo -e \
"We use ${MAGENTA}SSH Local Port Forwarding${NC} to establish an authenticated secure connection
between the web browser on your desktop/workstation and BTC RPC Explorer on your
zHIVErbox. As soon as the SSH connection is established, BTC RPC Explorer will
be started. And it will be terminated again when the SSH connection is closed.
"
    press_any_key
    echo -e \
"Here are the launch commands you need to run in a separate console/terminal on
your workstation:

${BOLD}For Bitcoin MAINNET${NC}
  ${ORANGE}ssh user@`get_local_ipv4_addr` -L 3002:localhost:3002 -t `basename $WRAPPER`${NC}
  ${ORANGE}ssh user@`get_local_cjdns_addr` -L 3002:localhost:3002 -t `basename $WRAPPER`${NC}

${BOLD}For Bitcoin TESTNET${NC}
  ${ORANGE}ssh user@`get_local_ipv4_addr` -L 3002:localhost:3002 -t `basename $WRAPPER` testnet${NC}
  ${ORANGE}ssh user@`get_local_cjdns_addr` -L 3002:localhost:3002 -t `basename $WRAPPER` testnet${NC}
"
}

# main script
echo ""
display_alert "Installation of BTC RPC Explorer on zHIVErbox" "" ""
echo -e \
"This tool is intended to be a simple, self-hosted explorer for the Bitcoin
blockchain, driven by RPC calls to your own bitcoind node. This tool is easy to
run but currently lacks features compared to database-backed explorers.
"

press_any_key

build_btcrpcexplorer
install_btcrpcexplorer
configure_firewall
display_alert "Installation of btc-rpc-explorer" "COMPLETE" "ext"
echo ""
press_any_key
show_manual
# don't ask to install again
touch $NO_REMIND_SETUP_FILE
