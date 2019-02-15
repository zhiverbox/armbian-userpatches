#!/bin/bash

# profile.d scripts are sourced, so DONT'T use exit but return instead

. /opt/zhiverbox/lib/bash/common.sh

# only do this for interactive shells
assert_interactive

POST_USER_SETUP_FILE=/etc/zhiverbox/.post_user_setup

# path and name of the SSH public key to use for authentication
# ATTENTION!!! MUST BE IN SYNC WITH: 
# install-zhiverbox.sh
SSH_AUTH_KEY=/etc/zhiverbox/ssh_auth_key.pub

# if post user setup was done already, sliently return
[[ ! -f $POST_USER_SETUP_FILE ]] && return

disable_root_account()
{
    # zHIVErbox disables root, so all admin actions are audited (/var/log/auth.log)
    display_alert "Disabling root account now..." "passwd -l root" ""
    passwd -l root
    echo -e \
"The ${RED}'root'${NC} account is disabled now on the zHIVErbox. From now on you have to
login with the ${GREEN}'user'${NC} account and run all admin commands via ${ORANGE}sudo${NC}."
    echo ""
    press_any_key

    display_alert "Disallow SSH root login..." "/etc/ssh/sshd_config" ""
    echo -e \
"Changing the sshd_config file might trigger a warning after reboot when you
try to connect via SSH again. ${MAGENTA}The warning will look like:${NC}

    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
    Someone could be eavesdropping on you right now (man-in-the-middle attack)!
    It is also possible that a host key has just been changed.
"
    press_any_key
    echo -e \
"${GREEN}The latter is the case.${NC} It's because we changed the config to disable the 'root
account' login. Just follow the instructions in the warning when you see it,
using the 'ssh-keygen -f' command to fix this.
"
    press_any_key
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    display_alert "Logins with 'root' via SSH or any other console have been disabled." "" "ext"
    echo ""
    press_any_key
}

enable_ssh_pubkey_for_user()
{
    # copy ssh pubkey for user login placed by zHIVErbox installer
    local authkeysfile=/home/user/.ssh/authorized_keys
    display_alert "Enabling SSH pubkey authentication for 'user' account..." "$authkeysfile" ""

    if [ -f $SSH_AUTH_KEY ]; then
        sudo -u user mkdir -m 700 /home/user/.ssh 2>/dev/null
        sudo -u user install -m 600 /dev/null $authkeysfile
        echo "# public key provided by zHIVErbox installer" > $authkeysfile
        cat $SSH_AUTH_KEY >> $authkeysfile
        display_alert "Enabled SSH public key authentication for account:" "user" "ext"
        display_alert "Disabling SSH password authentication for all accounts..." "/etc/ssh/sshd_config" ""
        sed -i 's/^.*PasswordAuthentication\s.*$/PasswordAuthentication no/' /etc/ssh/sshd_config
        display_alert "Disabled SSH password logins" "" "ext"
        echo ""
        press_any_key

        # fetch various local addresses
        cjdnsaddr=$(ip add | grep "inet6 fc" | awk '{ print $2 }' | sed 's/\/8//')
        onionaddr=$(cat /var/lib/tor/ssh_hidden_service/hostname)
        ipv4addr=$(ip route get 1 | awk '{print $NF;exit}')

        # show explanation how to connect
        echo -e \
"From now on you can only login to this zHIVErbox with the ${GREEN}'user'${NC} account
and pubkey authentication only. Assuming the private key is in the ~/.ssh/
directory of your workstation, you can connect to this zHIVErbox via:

    ${ORANGE}ssh user@`hostname`${NC}

or via its permanent Cjdns address:

    ${ORANGE}ssh user@${cjdnsaddr}${NC}

or via its Tor Hidden Onion Service address:

    ${ORANGE}torsocks ssh user@${onionaddr}${NC}

or via it's current (temporary?) IPv4 address:

    ${ORANGE}ssh user@${ipv4addr}${NC}

"
        display_alert "You should test these commands in a parallel terminal now..." "" "todo"
        echo -e "${MAGENTA}Hint: SHIFT+CTRL+T usually opens a new terminal tab (on Ubuntu)${NC}"
        echo ""
        press_any_key
    fi
}

# main script
echo ""
display_alert "Starting zHIVErbox post-user-setup customization..." "" "todo"
press_any_key

# disable root
disable_root_account

# enable ssh public key authentication
enable_ssh_pubkey_for_user

echo ""
display_alert "zHIVErbox post-user-setup customization complete!" "" "ext"
echo ""
rm -f $POST_USER_SETUP_FILE
press_any_key
