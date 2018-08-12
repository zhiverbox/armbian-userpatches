#!/bin/bash

# meta info for list_available_installers.sh
SNAME="zHIVErbox KadNode Setup"
SVERSION="0.1.0"

[[ -z ${ZHIVERBOX_HOME} ]] && echo "\$ZHIVERBOX_HOME environment variable not set!" && exit 1
. $ZHIVERBOX_HOME/lib/bash/common.sh
. $ZHIVERBOX_HOME/lib/bash/install-helpers.sh

# get the path to this script
SRC=${BASH_SOURCE[0]}

if [[ $EUID != 0 ]]; then
    display_alert "KadNode setup requires admin priviliges, trying to use sudo" "" "wrn"
    sudo -E bash "$SRC" "$@"
    exit $?
fi

KADNODE_USER=kadnode
KADNODE_HOME=/run/kadnode
KADNODE_CONFIG=/etc/kadnode/kadnode.conf
KADNODE_PRIVKEY=$(dirname $KADNODE_CONFIG)/key.pem
KADNODE_PUBKEY=$(dirname $KADNODE_CONFIG)/key.pub
KADNODE_DEFAULT_PORT=6881

NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_kadnode_setup

ask_change_port() {
	display_alert "Change default port" "" ""
	echo -e \
"By default, KadNode uses the same port (UDP 6881) as BitTorrent. If you have 
IPv4 and your zHIVErbox is behind a NAT gateway/router, you might want to change
this port to something which is unique in your local network and doesn't 
conflict with other devices that run BitTorrent. In any case, you need to make 
sure your Internet router doesn't block this port for incoming (unsolicited) 
connections and - in the case of IPv4+NAT - forwards it to your zHIVErbox.
"
	read -p "$UINPRFX Do you want to change the default KadNode UDP port (6881)? (y/n) " choice
	case $choice in
		y|Y|yes|YES ) echo "";;
		* ) echo "" && KADNODE_PORT=$KADNODE_DEFAULT_PORT && return 0;;
	esac
	
	while : ; do 
		read -p "$UINPRFX New UDP port for KadNode (0 to 65535): " KADNODE_PORT
	
		# check if user provided a vaild UDP port
		if echo $KADNODE_PORT | grep -qE '^([0-9]{1,4}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'; then
			
			# add or modify --port argument in kadnode config
			if grep -q '^--port ' $KADNODE_CONFIG; then
				sed -i "s/^--port .*$/--port $KADNODE_PORT/" $KADNODE_CONFIG
			else
				echo "--port $KADNODE_PORT" >> $KADNODE_CONFIG
			fi
			
			break # exit the while loop and continue
		else
			display_alert "Please enter a valid UDP port!" "https://en.wikipedia.org/wiki/Port_(computer_networking)" "err"
		fi
	done
}

generate_key()
{
	local genkeycmd="kadnode --bob-create-key $KADNODE_PRIVKEY"
	display_alert "Generating public/private key" "$genkeycmd" ""
	
	local genkeyout=$(mktemp)
	$genkeycmd > $genkeyout
	cat $genkeyout | sed "s/^/${SED_INTEND}/"
	
	# write public key to a file for convenience
	if grep -q '.p2p' $genkeyout; then
		cat $genkeyout | grep .p2p | awk '{print $3}' > $KADNODE_PUBKEY
		echo "Wrote public key to $KADNODE_PUBKEY" | sed "s/^/${SED_INTEND}/"
	fi
}

explain_key() {
	echo -e \
"
Your KadNode public key with the '.p2p' extension works like a domain name: 
  ${GREEN}`cat $KADNODE_PUBKEY`${NC}
"
	echo -e \
"Other KadNode users can use it to resolve your current IPv4 and IPv6 address to 
make inbound connection attempts with your zHIVErbox. While this could be used
with any application, we recommend to use it only for establishing authenticated 
meshnet connections like Cjdns - and then use Cjdns for all the other 
applications (if they have IPv6 support).
"
	press_any_key
	
	echo -e \
"With Cjdns + KadNode you should be aware of the following 3 layers of security:
  1. Only the people (devices) whom you tell your KadNode public key can resolve 
     your current legacy Internet address.
  2. In addtion, only the people (devices) you have given Cjdns access 
     credentials (a Cjdns password) can really establish a Cjdns connection with
     your zHIVErbox.
  3. In addition, only the applications allowed in the zHIVErbox firewall (ferm) 
     can be reached via Cjdns.
     
However, 1. and 2. are not very strong because it requires trusting the people 
(devices) you give these information to not share/leak it with others. So you
should be selective whom you tell your KadNode public key and whom you give a 
Cjdns password.
"

	press_any_key
	
	echo -e "${BOLD}Sounds complicated! Why don't we just use Tor or I2P for everything?${NC}"
	press_any_key
	echo -e \
"                                                                                 
  1. Not every application supports Tor or I2P. Cjdns support is transparent 
     for all (IPv6 capable) applications, due to it's IPv6 compatibility. 
     And Cjdns gives you end-to-end encrypted communication, which also not 
     every application has out-of-the-box.
  2. Tor and I2P are built for \"talking to strangers\" on the Internet. Random
     people you don't trust. And for hiding from a \"global adversary\" the fact 
     that two people / devices are communicating with each other. This comes at 
     the cost of the performance penalty of mixing networks (mixnets).

However, not all applications / use cases require anonymity or protection from 
a global adversery. Hence, for peer-to-peer applications with people you trust 
anyway, you don't have to take the performance penalty of a mixing network like 
Tor and I2P. Using Cjdns instead is still more secure than using the plain, 
legacy Internet directly.

Security is a game of tradeoffs. No tradeoffs, no security! More security, more 
tradeoffs! It's your decision!
"
	press_any_key
	
	echo -e "${BOLD}Give me some example use cases for Cjdns + KadNode please?${NC}"
	press_any_key
	echo -e \
"                                                                                 
  1. IPFS connections with people you trust but who are too far away to mesh 
     with them directly (WIFI/LAN).
  2. Lightning payment channels with people you trust but who are too far away 
     to mesh with them directly (WIFI/LAN).
"
	press_any_key
}

config_firewall()
{
	local fwrulesconf=/etc/ferm/ferm.conf
	display_alert "Configuring ferm firewall for KadNode..." "${fwrulesconf}" ""
	sed -i "s/^def $kadnode_port = /def $kadnode_port = $KADNODE_PORT/" $fwrulesconf
	
	# explain KadNode configuration
	echo -e \
"Your zHIVErbox will have KadNode running on UDP port $KADNODE_PORT for
both - outbound and inbound connections.
  * outbound - to resolve and authenticate other KadNodes IP addresses via DHT
  * inbound  - to be authenticatable by other KadNodes

Please make sure that your Internet router/gateway doesn't block this port and 
- in case of IPv4 - \"Port Forwarding\" to your zHIVErbox is setup. 
There are different mechanisms existing, depending on your router:
  * 'Automatic Port Forwarding' via UPnP (Universal Plug 'n Play)
  * 'Dynamic Port Forwarding' via a trigger port
  * 'Static Port Forwarding' via fixed mappings
  
Please consult the manual of your Internet router which method is supported and
how to configure it.
"
	press_any_key
	
	display_alert "Restarting ferm firewall..." "systemctl restart ferm" ""
	systemctl restart ferm
}

start_kadnode_daemon()
{
	display_alert "Starting KadNode daemon..." "systemctl start kadnode" ""
	systemctl start kadnode
	
	display_alert "Automatically start KadNode on (re-)boot..." "systemctl enable kadnode" ""
	systemctl enable kadnode
	
	display_alert "KadNode setup complete. Check your connection with:" "kadnode-ctl status" "ext"
	echo ""
	
	# don't ask to setup kadnode again
	touch $NO_REMIND_SETUP_FILE
	
	press_any_key
}

hint_cjdns_config()
{
	display_alert "${BOLD}How do I connect to other Cjdns peers via KadNode?${NC}" "" "todo"
	press_any_key
	echo -e \
"                                                                                 
Just edit the file ${ORANGE}/etc/cjdns-dynamic.conf${NC} and add the peering credentials 
they gave you. Restart 'cjdns-dynamic service' after editing the config file:

  ${ORANGE}sudo systemctl restart cjdns-dynamic${NC}
"
	press_any_key
}

# main script
echo ""
display_alert "Setup KadNode on zHIVErbox" "" ""
ask_change_port
generate_key && explain_key
config_firewall
start_kadnode_daemon
hint_cjdns_config
