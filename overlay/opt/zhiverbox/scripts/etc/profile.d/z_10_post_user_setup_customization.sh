#!/bin/bash

# profile.d scripts are sourced, so DONT'T use exit but return instead

. /opt/zhiverbox/lib/bash/common.sh

# only do this for interactive shells
assert_interactive

POST_USER_SETUP_FILE=/etc/zhiverbox/.post_user_setup

SSH_USER_KEY=/etc/zhiverbox/id_ecdsa.pub

# if post user setup was done already, sliently return
[[ ! -f $POST_USER_SETUP_FILE ]] && return

disable_root_account()
{
	# zHIVErbox disables root, so all admin actions are audited (/var/log/auth.log)
	display_alert "Disabling root account now..." "passwd -l root" ""
	echo -e \
"The ${RED}'root'${NC} account will be disabled on the zHIVErbox by default. So you have to 
login with the ${GREEN}'user'${NC} account and run all admin commands via ${ORANGE}sudo${NC}."
	passwd -l root
	display_alert "Disallow SSH root login..." "/etc/ssh/sshd_config" ""
	sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
	display_alert "Logins with 'root' via SSH or any other console have been disabled." "" "ext"
	echo ""
	press_any_key
}

enable_ssh_pubkey_for_user()
{
	# copy ssh pubkey for user login placed by zHIVErbox installer
	authkeysfile=/home/user/.ssh/authorized_keys
	display_alert "Enabling SSH pubkey authentication for 'user' account..." "$authkeysfile" ""
	
	if [ -f $SSH_USER_KEY ]; then
		mkdir /home/user/.ssh 2>/dev/null
		echo "# public key provided by zHIVErbox installer" >> $authkeysfile
		cat $SSH_USER_KEY >> $authkeysfile
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
"From now on you can only login to this zHIVErbox via the ${GREEN}'user'${NC} account 
via pubkey authentication only. Assuming the private key is in the ~/.ssh/
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

replace_default_ssh_boot_key()
{
	display_alert "Replace default SSH key for zHIVErbox boot system" "" ""
	echo -e \
"We now replace the default SSH key of the zHIVErbox ${RED}boot system${NC}, so you
you can use just one single SSH key to connect to both - the 'boot system' and 
the 'root system'.
"
	press_any_key
	
	local dropbeardir=/etc/dropbear-initramfs
	
	# check if the public key is rsa, dsa or ecdsa
	if ! grep -qE '^([^#]+ )?(ssh-(dss|rsa)|ecdsa-sha2-nistp(256|384|521)) ' "$SSH_USER_KEY"; then
		display_alert "The public key's signature algorithm is not supported by dropbear/initramfs." "$SSH_USER_KEY" "err"
		echo -e \
"You have to manually change the boot system's SSH authentication key:
    1. Copy a public key with a supported signature alogrithm (RSA, DSA or 
       ECDSA) into a file called ${ORANGE}$dropbeardir/authorized_keys${NC} 
    2. Delete existing 'id_ecdsa' and 'id_ecdsa.pub' keys in that folder
    3. Manually run ${ORANGE}sudo update-initramfs -uv${NC} to update the
       boot system (initramfs)
"
	else
		display_alert "Remove default public and private key" "rm dropbeardir/id_ecdsa*"
		rm $dropbeardir/id_ecdsa*
		display_alert "Copy individual public key" "cp $SSH_USER_KEY $dropbeardir"
		cp $SSH_USER_KEY $dropbeardir
	
		# update initramfs
		display_alert "Update boot system (initramfs) to contain new SSH key" "update-initramfs -uv" ""
		press_any_key
		update-initramfs -uv
		echo ""
		display_alert "Boot system now contains the same SSH public key as the root system." "" "ext"
	
		local dropbearopts=$(grep DROPBEAR_OPTIONS $dropbeardir/config | sed 's/DROPBEAR_OPTIONS=//; s/"//g')
		press_any_key
				echo -e \
"From now on you can login to this zHIVErbox's ${RED}boot system${NC} via:
	${ORANGE}ssh $dropbearopts root@boot.`hostname`${NC}
	
or via it's current (temporary?) IPv4 address:
	${ORANGE}ssh $dropbearopts root@${ipv4addr}${NC}

Cjdns or Tor access are ${BOLD}not available${NC} on the 'limited' boot system.
"
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

# use the same ssh public key for initramfs authentication as well
replace_default_ssh_boot_key

echo ""
display_alert "zHIVErbox post-user-setup customization complete!" "" "ext"
echo ""
rm -f $POST_USER_SETUP_FILE
press_any_key
