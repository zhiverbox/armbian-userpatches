#!/bin/bash

# meta info for list_available_installers.sh
SNAME="zHIVErbox IPFS Installer"
SVERSION="0.1.0"

[[ -z ${ZHIVERBOX_HOME} ]] && echo "\$ZHIVERBOX_HOME environment variable not set!" && exit 1
. $ZHIVERBOX_HOME/lib/bash/common.sh
. $ZHIVERBOX_HOME/lib/bash/install-helpers.sh

# get the path to this script
SRC=${BASH_SOURCE[0]}

if [[ $EUID != 0 ]]; then
    display_alert "IPFS setup requires admin priviliges, trying to use sudo" "" "wrn"
    sudo -E bash "$SRC" "$@"
    exit $?
fi

# Download URLs for IPFS
URL_IPFS_BASE="https://ipfs.io/ipns/dist.ipfs.io/go-ipfs"
URL_IPFS_VERSIONS="$URL_IPFS_BASE/versions"

IPFS_USER=ipfsd
IPFS_GROUP=ipfs
IPFS_DATADIR_RELATIVE=".ipfs"
IPFS_DEFAULT_PORT=4001
IPFS_API_PORT=5001
IPFS_GATEWAY_PORT=8080

make_dir() {
  dir=$1;
  mkdir -p $dir;
  chown $IPFS_USER:$IPFS_GROUP $dir
  chmod 755 $dir
}

make_mount_dir() {
  dir=$1;
  mkdir $dir;
  chown $IPFS_USER:$IPFS_GROUP $dir
  chmod 775 $dir
}

# doesn't work right now because ipfs-update doesn't support socks5 proxy (Tor)
install_via_ipfs_update()
{
	# math/bits is only available with Go 1.10
	display_alert "Install required Go 1.10 packages" "apt-get -y -q install -t stretch-backports golang-1.10-go" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install -t stretch-backports golang-1.10-go
    
    # golang.org (aka go.googlesource.com) seems to be blocking Tor traffic
    # therefore we have to install the golang crypto packages from the Debian repository
    display_alert "Install required Go crypto packages" "apt-get -y -q install -t stretch-backports golang-golang-x-crypto-dev" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install -t stretch-backports golang-golang-x-crypto-dev

	export GOPATH="/opt/go:/usr/share/gocode"
	mkdir /opt/go 2>/dev/null
	chown nobody:nogroup /opt/go
	display_alert "Install ipfs-update" "sudo -E -u nobody torsocks /usr/lib/go-1.10/bin/go get -u -f -v github.com/ipfs/ipfs-update" ""
	# we have to use the -f option because of the golang.org packages
    sudo -E -u nobody torsocks /usr/lib/go-1.10/bin/go get -u -f -v github.com/ipfs/ipfs-update
    
    display_alert "Install latest IPFS version" "torsocks /opt/go/bin/ipfs-update install latest" ""
    local instlog=$(mktemp)
    sudo -u nobody torsocks /opt/go/bin/ipfs-update --verbose install latest > $instlog
}

# our own zHIVErbox way to install IPFS
install_custom_approach()
{
	# download pre-built release
	download_via_clearnet
	
	display_alert "Continuing with installation of:" "$VERSION" ""
	cd $INSTALL_PATH
	display_alert "Installing to:" "$INSTALL_PATH" ""
	local tarcmd="tar -xvf $DOWNLOAD_PATH/$FILENAME"
	display_alert "Extracting release..." "$tarcmd" ""
	local tarout=$($tarcmd)
	local tardir=$(dirname $(echo $tarout | awk '{print $1}' | sed 's~/$~~'))
	mv $tardir $tardir-$VERSION || rm -rf $tardir
	tardir=$tardir-$VERSION
	
	# copy ipfs binary
	display_alert "Installing 'ipfs' binary..." "/usr/local/bin/ipfs" ""
	install -o root -g root -m 0755 $tardir/ipfs /usr/local/bin/ipfs 2>/dev/null
	
	# setup daemon
	setup_daemon
}

download_via_clearnet()
{
	# fetch available versions
	display_alert "Checking available IPFS releases..." "$CMD_CURL_TOR \"$URL_IPFS_VERSIONS\"" ""
	local versions=$($CMD_CURL_TOR "$URL_IPFS_VERSIONS" 2>/dev/null | grep . | sort -Vr ) 
	if [[ -z $versions ]]; then
		display_alert "Could not fetch available IPFS releases. Please check your network connection!" "" "err"
		exit 1
	fi

	# detect local architecture
	local machine=$(uname -m)
	if [[ $machine == "armv7l" ]]; then
		ARCH="linux-arm"
	else 
		display_alert "Your hardware is not supported by this installer yet" "$machine" "err"
		display_alert "Please install IPFS manually following:" "https://ipfs.io/docs/install/" "todo"
	fi
	
	# select version
	select_version $versions
	
	FILENAME=$(basename $URL)

	mkdir -p $INSTALL_PATH 2>/dev/null
	cd $INSTALL_PATH
	DOWNLOAD_PATH=$INSTALL_PATH/downloads/$VERSION
	mkdir -p $DOWNLOAD_PATH
	chmod -R 777 $DOWNLOAD_PATH
	[[ ! -f $DOWNLOAD_PATH/$FILENAME ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $URL
	
	# unfortunately IPFS doesn't doesn't publish hashsums nor releases signed versions yet
	
#	[[ ! -f $DOWNLOAD_PATH/SHA256SUMS.asc ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $(dirname $URL)/SHA256SUMS.asc	
#	display_alert "Downloading signature key for version" "$VERSION" ""
#	local signkeyurl='$URL_IPFS_BASE/releases.asc'
#	local signkey=$DOWNLOAD_PATH/$(basename $signkeyurl)
#	[[ ! -f $signkey ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $signkeyurl
#	display_alert "Import signature key for selected version" "$(basename $signkeyurl)" ""
#	gpg --import $signkey 2>&1 | sed "s/^/${SED_INTEND}/"

	SHASUM=$(sha256sum $DOWNLOAD_PATH/$FILENAME)
	display_alert "This IPFS release is not signed!" "https://github.com/ipfs/go-ipfs/issues/957" "wrn"
	echo -e \
"Unfortunately the IPFS team does not:
1. Provide ${BOLD}signed${NC} prebuilt releases (yet).
   see: https://github.com/ipfs/go-ipfs/issues/957
2. Publish hashsums (SHA-256 or SHA-512) for the prebuilt releases (yet)
3. Use ${BOLD}signed${NC} commits for their Git repository (yet)

This means, zHIVErbox can't verify the authenticity of the downloaded IPFS
release. Allthough we did the best we can to avoid a targeted attack by 
downloading over Tor, we're not safe from broader attacks on the IPFS download
server or various DNS attacks.
"
	echo -e "${RED}Should YOU trust this downloaded file?${NC}"
	press_any_key
	echo -e \
"As always: ${BOLD}DON'T TRUST! VERIFY!${NC}
Here is the computed SHA-256 of the file that we just downloaded:
    
    ${ORANGE}sha256sum $DOWNLOAD_PATH/$FILENAME${NC}
    ${MAGENTA}${SHASUM}${NC}    
"
	press_any_key
	echo -e \
"Here is some guidance what you can do:
* Download the same file via multiple different networks (Tor, Cjdns, land line, 
  mobile data, public Wifi hotpots) and various different devices and operating
  systems. Compute the sha256sum and compare all the downloads.
* Ask people you trust to do the same.

This way, you can at least limit the probability of an individual, targeted 
attack on your system only.
"
	while [[ -z $goodchoice ]]; do
		read -p "$UINPRFX Do you want to continue with the installation? (y/n) " choice
		case "$choice" in 
		  y|Y|yes|YES ) local goodchoice=1 && echo "";;
		  n|N|no|NO ) exit 1;;
		esac
	done	
}

select_version()
{
	PS3="> Select number: " 
    select VERSION in $@;
    do
	    echo "" && display_alert "Selected release:" "$VERSION" "ext"
	    break
    done
    
    # test if selected version and architecture exists
	local prefix="go-ipfs"
	URL=$URL_IPFS_BASE/$VERSION/${prefix}_${VERSION}_${ARCH}.tar.gz
	if $CMD_CURL_TOR --output /dev/null --silent --head --fail "$URL"; then
  		display_alert "Downloading binary from:" "$URL" ""
	else
  		display_alert "The selected version doesn't seem to have a binary for your architecture (yet)." "${prefix}_${VERSION}_${ARCH}.tar.gz" "err"
  		display_alert "Please select a different version!" "" ""
  		select_version $@
	fi
}

setup_daemon()
{
	# create group for ipfs
	display_alert "Creating system group 'ipfs' ..." "/etc/group" ""
	egrep -i "^$IPFS_GROUP:" /etc/group &>/dev/null
	if [ $? -ne 0 ]; then
	  groupadd $IPFS_GROUP
	fi
	local ipfs_group_id=$(grep $IPFS_GROUP /etc/group|cut -d: -f3)

	# create a system user for ipfs
	display_alert "Creating system user 'ipfsd' ..." "/etc/passwd" ""
    if [[ -z $(getent passwd $IPFS_USER >/dev/null) ]]; then
        adduser --quiet \
		    --system \
		    --disabled-password \
		    --home $INSTALL_PATH \
		    --no-create-home \
		    --shell /bin/false \
		    --gid $ipfs_group_id \
		    $IPFS_USER
	fi
	
	# setup .ipfs data directory
	IPFS_DATADIR=$INSTALL_PATH/$IPFS_DATADIR_RELATIVE
	display_alert "Creating IPFS data directory..." "$IPFS_DATADIR" ""
	if [[ ! -d $IPFS_DATADIR ]]; then make_dir $IPFS_DATADIR; fi
	
	# Add the default user (1000) to the group, so it can access the /ipfs /ipns mount points
	local default_user=$(id -nu 1000)
	display_alert "Adding '$default_user' account to '$IPFS_GROUP' group ..." "usermod --append --groups $IPFS_GROUP $default_user" ""
	usermod --append --groups $IPFS_GROUP $default_user
	
	# Add IPFS_PATH to default bashrc
	local default_bashrc=/etc/bash.bashrc
	display_alert "Adding IPFS_PATH default bashrc ..." "$default_bashrc" ""
	if grep -q IPFS_PATH $default_bashrc; then
		sed -i "s|.*export IPFS_PATH=.*|export IPFS_PATH=$IPFS_DATADIR|" $default_bashrc
	else
		echo "# location of the IPFS repository (needed by the 'ipfs' command)" >> $default_bashrc
		echo "export IPFS_PATH=$IPFS_DATADIR" >> $default_bashrc
	fi

	if [[ ! -f $IPFS_DATADIR/config ]]; then
    	display_alert "Initializing IPFS repository..." "sudo -H -u $IPFS_USER ipfs init" "" 
		echo -e "This can take some time to generate the keys..."
		sudo -H -u $IPFS_USER ipfs init
	fi
	
	# export IPFS_PATH for the current login session as well in case preceding scripts need it
	export IPFS_PATH=$IPFS_DATADIR 
	
	display_alert "Setting up IPFS and IPNS FUSE mount points..." "/ipfs and /ipns" "" 
	sudo -H -u $IPFS_USER ipfs config Mounts.FuseAllowOther --bool true
	# Allow non-root users to specify the allow_other mount option
	sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
	# fuse mountpoints for ipfs and ipns
    if [[ ! -d /ipfs ]]; then make_mount_dir /ipfs; fi
	if [[ ! -d /ipns ]]; then make_mount_dir /ipns; fi
	
	# enable filestore to save disk space
	# see https://github.com/ipfs/go-ipfs/blob/master/docs/experimental-features.md#ipfs-filestore
	sudo -H -u $IPFS_USER ipfs config --json Experimental.FilestoreEnabled true
	
	# don't leak our local ip addresses via the swarm, only announce loopback and cjdns to swarm
	# see https://github.com/ipfs/go-ipfs/blob/master/docs/config.md#addresses
	display_alert "Only listen on local loopback and Cjdns interface" "ipfs config Addresses.Swarm" ""
	echo -e \
"zHIVErbox IPFS setup listens by default only on the local loopback interfaces
and the Cjdns interface for swarm connections. This avoids leaking your other 
IP addresses via IPFS. In result, you will be connected to the public IPFS swarm 
as long as you are connected to at least one Hyperboria (Cjdns) peer. 
"	
	local cjdnsaddr=$(get_local_cjdns_addr)
	# the order of address declaration seems to matter, cjdns address needs to be first
	local listenaddresses="[
\"/ip6/$cjdnsaddr/tcp/$IPFS_DEFAULT_PORT\",
\"/ip6/::1/tcp/$IPFS_DEFAULT_PORT\",
\"/ip4/127.0.0.1/tcp/$IPFS_DEFAULT_PORT\"
]"
	sudo -H -u $IPFS_USER ipfs config --json Addresses.Swarm "$listenaddresses"
	sudo -H -u $IPFS_USER ipfs config --json Addresses.Swarm | jq
	press_any_key
	echo -e \
"You can change the IPFS config manually if you prefer another setup.
See https://github.com/ipfs/go-ipfs/blob/master/docs/config.md#addresses
"	
	# add Hyperboria bootstrap peers
	add_hyperboria_bootstrapping_peers
	
	display_alert "Installing IPFS system service..." "systemctl enable ipfsd" ""
	cp $ZHIVERBOX_HOME/scripts/etc/systemd/system/ipfsd.service /etc/systemd/system/
	systemctl enable ipfsd
	
	display_alert "IPFS installation complete." "$(ipfs --version)" "ext"
}

config_firewall()
{
	local fwrulesdir=/etc/ferm/ferm.d
	display_alert "Configuring ferm firewall for IPFS..." "${fwrulesdir}/ipfs.*" ""
	mkdir -p $fwrulesdir 2>/dev/null
	
	# copy all ipfs related firewall rules
	local backupdirname=$(echo "_backups/`date +%s`_ipfs")
	for source in $ZHIVERBOX_HOME/scripts$fwrulesdir/ipfs.*; do
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
			sed -i "s/{{IPFS_USER}}/${IPFS_USER}/" $target
			sed -i "s/{{IPFS_DEFAULT_PORT}}/${IPFS_DEFAULT_PORT}/" $target
			sed -i "s/{{IPFS_API_PORT}}/${IPFS_API_PORT}/" $target
			sed -i "s/{{IPFS_GATEWAY_PORT}}/${IPFS_GATEWAY_PORT}/" $target
			
			# rename the target to strip the .src extension
			mv $target $(echo "$target" | sed 's~.src$~~')
		fi
	done
	
	display_alert "Restarting ferm firewall..." "systemctl restart ferm" ""
	systemctl restart ferm
}

add_hyperboria_bootstrapping_peers()
{
	display_alert "Adding Hyperboria IPFS bootstrap peers..." "ipfs config --json Bootstrap" ""
	# known hyperboria addresses of some of the default bootstrap peers
	local peer1='"/ip6/fc8f:dcbf:74b9:b3b9:5305:7816:89ac:53f3/tcp/4001/ipfs/QmZMxNdpMkewiVZLMRxaNxUeZpDUb34pWjZ1kZvsd16Zic"'
	local peer2='"/ip6/fc4e:5427:3cd0:cc4c:4770:25bb:a682:d06c/tcp/4001/ipfs/QmSoLSafTMBsPKadTEgaXctDQVcqN88CNLHXMkTNwMKPnu"'
	local peer3='"/ip6/fcd8:a4e5:3af7:557e:72e5:f9d1:a599:e329/tcp/4001/ipfs/QmSoLV4Bbm51jM9C4gDYZQ9Cy3U6aXMJDAbzgu2fzaDs64"'
	local peer4='"/ip6/fc29:9fda:3b73:c1d2:9302:31e3:964c:144c/tcp/4001/ipfs/QmSoLer265NRgSp2LA3dPaeykiS1J6DifTC88f5uVQKNAd"'
	local cjdnspeers="[$peer1,$peer2,$peer3,$peer4]"
	
	local existing_bootstrap=$(sudo -H -u $IPFS_USER ipfs config --json Bootstrap)
	if ! echo $existing_bootstrap | grep -q $peer1; then
		# cjdns peers have not been added before
		local merged_bootstrap=$(sudo -H -u $IPFS_USER ipfs config --json Bootstrap | jq -c -M ".+ $cjdnspeers")
		sudo -H -u $IPFS_USER ipfs config --json Bootstrap "$merged_bootstrap"
	fi
	# display new bootstrap	
	sudo -H -u $IPFS_USER ipfs config --json Bootstrap | jq
}

start_ipfs_daemon()
{
	display_alert "Starting IPFS daemon..." "systemctl start ipfsd" ""
	systemctl start ipfsd
	systemctl --no-pager status ipfsd
	
	display_alert "IPFS installation complete. Check your connection with:" "ipfs swarm peers" "ext"
	echo ""
	press_any_key
}

# main script
echo ""
display_alert "Installation of IPFS on zHIVErbox" "" ""
ask_install_path ipfs "IPFS repository"
install_custom_approach
config_firewall
start_ipfs_daemon
echo "QmbyP775SbWYwASfYHEFfpszwj99nRZSxiFfjjAcwwuVSB" > $ZHIVERBOX_IPFS_REPO
