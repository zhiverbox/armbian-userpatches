#!/bin/bash

# meta info for list_available_installers.sh
SNAME="zHIVErbox Bitcoin Core Installer"
SVERSION="0.1.0"

ZHIVER_LOG=~/zhiverbox_install-bitcoind.log
touch $ZHIVER_LOG

[[ -z ${ZHIVERBOX_HOME} ]] && echo "\$ZHIVERBOX_HOME environment variable not set!" && exit 1
. $ZHIVERBOX_HOME/lib/bash/common.sh
. $ZHIVERBOX_HOME/lib/bash/install-helpers.sh

# get the path to this script
SRC=${BASH_SOURCE[0]}

if [[ $EUID != 0 ]]; then
    display_alert "bitcoind setup requires admin priviliges, trying to use sudo" "" "wrn"
    sudo -E bash "$SRC" "$@"
    exit $?
fi

BITCOIN_USER=bitcoind
BITCOIN_GROUP=bitcoin
BITCOIN_FILE_PREFIX=""
BITCOIN_LAYER1_NETWORK=mainnet
BITCOIN_DATADIR_RELATIVE=".bitcoin"
BITCOIN_DEFAULT_PORT=8883
BITCOIN_CONTROL_PORT=8332

# onion-grater filter doesn't work on zHIVErbox yet, so as a temporary workaround
# give bitcoind direct access to TOR's control port
TOR_CONTROL_PORT=9052

# timeout for IPFS operations
IPFS_TIMEOUT="5s"

# check IPFS support
if [[ -n $(ipfs --version 2>/dev/null) && -n $IPFS_PATH ]]; then
	display_alert "IPFS is available" "$IPFS_PATH" ""
	HAS_IPFS=true
fi

make_dir() {
  dir=$1;
  mkdir -p $dir;
  chown $BITCOIN_USER:$BITCOIN_GROUP $dir
  chmod 755 $dir
}

make_private_dir() {
  dir=$1;
  mkdir -p $dir;
  chown $BITCOIN_USER:$BITCOIN_GROUP $dir
  chmod 700 $dir
}

# try to get binary via content-addressable Internet (IPFS)
# we'll use the /ipfs and /ipns FUSE mountpoints and symbolic links to avoid
# storing the respective release files twice on the disk
get_via_ipfs()
{
	IPFS_MIRROR_PATH=/ipns/$(cat $ZHIVERBOX_IPFS_REPO | awk '{print $1}')/mirrors/bitcoin.org
	display_alert "Checking available Bitcoin releases in IPFS..." "$IPFS_MIRROR_PATH" "" 
	
	# select version
	local versions=$(timeout $IPFS_TIMEOUT ls $IPFS_MIRROR_PATH 2>/dev/null |  grep -o 'bitcoin-core.*' | sort -Vr)
	if [[ -n $versions ]]; then 
		select_version_via_ipfs $versions
		[[ $? != 0 ]] && return 1
	
		FILENAME=$(basename $RELEASE_IPFS_PATH)

		cd $INSTALL_PATH
		mkdir -p $INSTALL_PATH/downloads
		chmod -R 777 $INSTALL_PATH/downloads
		DOWNLOAD_PATH=$INSTALL_PATH/downloads/$VERSION
		rm -rf $DOWNLOAD_PATH 2>/dev/null
		ln -s $(dirname $RELEASE_IPFS_PATH) $INSTALL_PATH/downloads/

		#[[ ! -f $DOWNLOAD_PATH/$FILENAME ]] && ln -s $RELEASE_IPFS_PATH
		#[[ ! -f $DOWNLOAD_PATH/SHA256SUMS.asc ]] && ln -s $(dirname $RELEASE_IPFS_PATH)/SHA256SUMS.asc

		if version_ge $VERSION "0.11.0" ; then
			local signkeypath="$DOWNLOAD_PATH/laanwj-releases.asc"
		elif version_ge $VERSION "0.9.3"  ; then
			local signkeypath="$DOWNLOAD_PATH/laanwj.asc"
		elif version_le $VERSION "0.9.2.1"; then
			local signkeypath="$DOWNLOAD_PATH/gavinandresen.asc"
		fi
		display_alert "Import signature key for selected version" "gpg --import $signkeypath" ""
		gpg --import $signkeypath 2>&1 | sed "s/^/${SED_INTEND}/"
	
	else
		display_alert "We can't reach any IPFS node sharing the Bitcoin Core release directory right now." "" "err"
		display_alert "Trying fallback via legacy Internet." "" ""
		download_via_legacy_internet
	fi
	
}

select_version_via_ipfs()
{
	local versions=$@
	PS3="> Select number: " 
    select VERSION in $versions;
    do
	    echo "" && display_alert "Selected release:" "$VERSION" "ext"
	    break
    done
    
    # test if selected version and architecture is available
	local prefix=$(echo $VERSION | sed 's/-core//')
	RELEASE_IPFS_PATH=$IPFS_MIRROR_PATH/$VERSION/$prefix-$ARCH.tar.gz
	
	display_alert "Fetching release from IPFS:" "$RELEASE_IPFS_PATH" ""
	timeout $IPFS_TIMEOUT ipfs ls $RELEASE_IPFS_PATH
	if [[ $? = 124 ]]; then
  		display_alert "We can't reach any IPFS node sharing the selected version right now." "$prefix-$ARCH.tar.gz" "err"
  		display_alert "Trying fallback via legacy Internet!" "" ""
  		
  		RELEASE_LEGACY_URL=$(build_release_legacy_url $VERSION $ARCH)
  		local result=$(test_version_legacy_internet)
  		case $result in
  			OK 	) 
  				display_alert "Downloading release via legacy Internet:" "$RELEASE_LEGACY_URL" "";
  				return 1;;
  			* 	)
  				display_alert "The selected version doesn't seem to have a binary for your architecture (yet)." "$prefix-$ARCH.tar.gz" "err";
  				display_alert "Please select a different version!" "" "";
  				select_version $versions;;
  		esac
	fi
}

download_via_legacy_internet()
{
	# fetch available versions
	display_alert "Checking available Bitcoin releases via legacy Internet..." "$CMD_CURL_TOR 'https://bitcoin.org/bin/'" ""
	local versions=$($CMD_CURL_TOR 'https://bitcoin.org/bin/' 2>/dev/null | grep -o '"bitcoin-core-.*/"' | sed 's/["/]//g' | sort -Vr ) 
	if [[ -z $versions ]]; then
		display_alert "Could not fetch available Bitcoin releases. Please check you network connection!" "" "err"
		exit 1
	fi
	
	# select version
	select_version_legacy_internet $versions
	
	FILENAME=$(basename $RELEASE_LEGACY_URL)

	cd $INSTALL_PATH
	DOWNLOAD_PATH=$INSTALL_PATH/downloads/$VERSION
	[[ -L $DOWNLOAD_PATH ]] && rm -rf $DOWNLOAD_PATH
	mkdir -p $DOWNLOAD_PATH
	chmod -R 777 $DOWNLOAD_PATH
	[[ ! -f $DOWNLOAD_PATH/$FILENAME ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $RELEASE_LEGACY_URL
	[[ ! -f $DOWNLOAD_PATH/SHA256SUMS.asc ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $(dirname $RELEASE_LEGACY_URL)/SHA256SUMS.asc
	
	if   version_ge $VERSION "0.11.0" ; then
		local signkeyurl='https://bitcoin.org/laanwj-releases.asc'
	elif version_ge $VERSION "0.9.3"  ; then
		local signkeyurl='https://bitcoin.org/laanwj.asc'
	elif version_le $VERSION "0.9.2.1"; then
		local signkeyurl='https://bitcoin.org/gavinandresen.asc'
	fi
	display_alert "Downloading signature key for version" "$VERSION" ""
	local signkey=$DOWNLOAD_PATH/$(basename $signkeyurl)
	[[ ! -f $signkey ]] && $CMD_WGET_TOR -P $DOWNLOAD_PATH $signkeyurl
	display_alert "Import signature key for selected version" "gpg --import $signkey" ""
	gpg --import $signkey 2>&1 | sed "s/^/${SED_INTEND}/"
}

select_version_legacy_internet()
{
	PS3="> Select number: " 
    select VERSION in $@;
    do
	    echo "" && display_alert "Selected release:" "$VERSION" "ext"
	    break
    done
    
    RELEASE_LEGACY_URL=$(build_release_legacy_url $VERSION $ARCH)
    local result=$(test_version_legacy_internet)
	case $result in
		OK 	) 
			display_alert "Downloading binary via legacy Internet:" "$RELEASE_LEGACY_URL" "";;
		* 	)
			display_alert "The selected version doesn't seem to have a binary for your architecture (yet)." "$prefix-$ARCH.tar.gz" "err";
			display_alert "Please select a different version!" "" "";
			select_version_legacy_internet $@;;
	esac
}

build_release_legacy_url()
{
	local version=$1
	local arch=$2
	local prefix=$(echo $version | sed 's/-core//')
	echo "https://bitcoin.org/bin/$version/$prefix-$ARCH.tar.gz"
}

# test availability via location-addressable Internet (legacy Internet)
test_version_legacy_internet()
{
	# test if selected version and architecture exists
	if $CMD_CURL_TOR --output /dev/null --silent --head --fail "$RELEASE_LEGACY_URL"; then
  		echo "OK"
	else
  		echo "NA"
	fi
}

pin_on_ipfs()
{
	local filesize=$(du -h $FILENAME | awk '{print $1}')
	display_alert "IPFS pinning of release archive" "$FILENAME ($filesize)" "todo"
	echo -e \
"You can make a small contribution by adding (pinning) the downloaded realease 
to your IPFS node! This way other zHIVErboxes don't have to rely on bitcoin.org 
servers being available and you help making the Bitcoin ecosystem more resilient.
"
	read -p "$UINPRFX Pin $FILENAME ($filesize) on IPFS? (y/n) " choice
	case "$choice" in 
	  y|Y|yes|YES )
	    echo ""
	  	# follow download path (cd -P) to see if the release was already taken from IPFS
	  	cd -P $DOWNLOAD_PATH
	  	local current_dir=$(pwd)
	  	if [[ $current_dir =~ ^/ipfs/ ]]; then
	  		# just get the hash
	  		local dirhash=$(ipfs files stat $current_dir | head -n1)
	  	else
	  		# add the release to IPFS to get the hash
	  		local addcmd="ipfs add -r $DOWNLOAD_PATH"
	  		display_alert "Adding release directory to IPFS..." "$addcmd"
	  		local addout=$(mktemp)
	  		$addcmd > $addout
	  		cat $addout | sed "s/^/${SED_INTEND}/"
	  		local dirhash=$(cat $addout | tail -n1 | awk '{print $2}')
	  		# replace local copy with link to /ipfs
	  		local release_dir_name=$(basename $DOWNLOAD_PATH)
	  		cd ..
	  		rm -rf $release_dir_name && ln -s /ipfs/$dirhash $release_dir_name
	  	fi
	  	
	  	# pin the hash
	  	local pincmd="ipfs pin add /ipfs/$dirhash"
	  	display_alert "Pinning release on local IPFS node..." "$pincmd" ""
	  	$pincmd | sed "s/^/${SED_INTEND}/"
	  	echo ""
	  	;;
	  n|N|no|NO ) echo "";;
	esac
}

download_and_verify()
{
	# detect local architecture
	local machine=$(uname -m)
	if [[ $machine == "armv7l" ]]; then
		ARCH="arm-linux-gnueabihf"
	else 
		display_alert "Your hardware is not supported by this installer yet" "$machine" "err"
		display_alert "Please install bitcoin core manually from:" "https://bitcoin.org/en/download" "todo"
	fi

	# get release archive
	[[ $HAS_IPFS ]] && get_via_ipfs || download_via_legacy_internet
	
	# verify
	cd $DOWNLOAD_PATH
	local checkcmd="sha256sum -c --ignore-missing SHA256SUMS.asc"
	echo ""
	display_alert "Verifying checksum of downloaded Bitcoin version..." "$checkcmd" ""
	local checkerr=$(mktemp)
	local checkresult=$($checkcmd 2>$checkerr)
	if [[ -n $checkresult ]]; then
		echo -e "${GREEN}$checkresult${NC}\n" | sed "s/^/${SED_INTEND}/"
		local verifycmd="gpg2 --verify SHA256SUMS.asc"
		display_alert "Verifying signature of SHA256 checksum..." "$verifycmd" ""
		local gpgverifyresult=$($verifycmd 2>&1)
		gpgverifyresult=$(sed "s/^gpg: Good signature from.*$/${SED_BGREEN}&${SED_NC}/" <<<$gpgverifyresult)
		gpgverifyresult=$(sed "s/^gpg: WARNING: This key is not certified with a trusted signature!$/${SED_MAGENTA}&${SED_NC}/" <<<$gpgverifyresult)
		gpgverifyresult=$(sed "s/^gpg: .*There is no indication that the signature belongs to the owner.$/${SED_MAGENTA}&${SED_NC}/" <<<$gpgverifyresult)
		echo -e "$gpgverifyresult" | sed "s/^/${SED_INTEND}/"
		
		if grep -q "WARNING: This key is not certified with a trusted signature!" <<<$gpgverifyresult; then
			echo -e "\n${RED}Wait a second! What does the above ${MAGENTA}WARNING${RED} mean?${NC}"
			press_any_key
			echo -e \
"It means that ${BOLD}YOU${NC} don't trust the signature (yet)! Which is ${BOLD}not unusual${NC}, 
because you probably haven't met the person this signature belongs to in real 
life, right!? The good news is, the Bitcoin software we downloaded is valid 
(hasn't been tampered with) according to the signature. The not so good news is 
that you still have to decide now if you want trust that signature or not.
"
			echo -e "${RED}Should I trust this signature?${NC}"
			press_any_key
			echo -e \
"As always: ${BOLD}DON'T TRUST! VERIFY!${NC}
Here is some guidance what you can do:
* Try to meet the person who signed the release in person and confirm the
  above fingerprint with them.
* Try to find multiple people you already trust and who met the above shown 
  person who signed the release and confirmed the fingerprint. You might find 
  these people at local Bitcoin meetups.
* Check and compare multiple different sources (websites, forums, IRC channels) 
  for the above fingerprint. 
  - Use different networks while doing this:
    Tor, Cjdns, land line, mobile data, public Wifi hotpots
  - Use different devices and operating systems while doing this:
    Laptop, smartphone, tablet, a friends phone, ...
"
			while [[ -z $goodchoice ]]; do
				read -p "$UINPRFX Do you want to continue with the installation? (y/n) " choice
				case "$choice" in 
				  y|Y|yes|YES ) local goodchoice=1 && echo "";;
				  n|N|no|NO ) exit 0;;
				esac
			done
			
			# pin on IPFS
			[[ $HAS_IPFS ]] && pin_on_ipfs
		fi
	else
		display_alert "Could not verify checksum of downloaded Bitcoin version." "" "err"
		cat $checkerr
		display_alert "Please select another version or install manually." "" ""
		download_and_verify
	fi
}

install_bitcoincore()
{
	# create group for bitcoin
	display_alert "Creating system group '$BITCOIN_GROUP' ..." "/etc/group" ""
	grep -i "^$BITCOIN_GROUP:" /etc/group &>/dev/null
	if [ $? -ne 0 ]; then
	  groupadd --system $BITCOIN_GROUP
	fi
	local bitcoin_group_id=$(grep -i "^$BITCOIN_GROUP:" /etc/group | cut -d: -f3)

	# create a system user for bitcoincore
	display_alert "Creating system user '${BITCOIN_USER}' ..." "/etc/passwd" ""
    if [[ -z $(getent passwd $BITCOIN_USER 2>/dev/null) ]]; then
        adduser --quiet \
		    --system \
		    --disabled-password \
		    --home $INSTALL_PATH \
		    --no-create-home \
		    --shell /bin/false \
		    --gid $bitcoin_group_id \
		    $BITCOIN_USER
	fi
	
	# workaround as long as onion-grater filter for Tor's control port doesn't work
	usermod --groups debian-tor --append $BITCOIN_USER
	
	# create bitcoincore home dir
	if [[ ! -d $INSTALL_PATH ]]; then make_dir $INSTALL_PATH; fi
	
	# create directory for btrfs blockchain snapshots
	if [[ $INSTALLFS == btrfs ]]; then
		local snapshotsdir="$INSTALL_PATH/_blockchain/snapshots_${BITCOIN_LAYER1_NETWORK}"
		display_alert "Creating parent directory for btrfs snapshots of ${BITCOIN_FILE_PREFIX}blockchain data..." "$snapshotsdir"
		if [[ ! -d $snapshotsdir ]]; then mkdir -p $snapshotsdir; fi
	
		# create directory for btrfs subvolume @current
		local blockchainvol="$INSTALL_PATH/_blockchain/@current_${BITCOIN_LAYER1_NETWORK}"
		display_alert "Creating btrfs subvolume for easy snapshots (backups) of ${BITCOIN_FILE_PREFIX}blockchain data..." "$blockchainvol"
		if [[ ! -d $blockchainvol ]]; then btrfs subvolume create $blockchainvol 2>&1 | sed "s/^/${SED_INTEND}/"; fi
		if [[ ! -d $blockchainvol/blocks ]]; then make_private_dir $blockchainvol/blocks; fi
		if [[ ! -d $blockchainvol/chainstate ]]; then make_private_dir $blockchainvol/chainstate; fi
	
		# automatic daily snapshots of @current subvolume
		local cronfile=/etc/cron.daily/${BITCOIN_FILE_PREFIX}blockchain-snp
		display_alert "Setup automatic daily snapshots of ${BITCOIN_FILE_PREFIX}blockchain data..." "$cronfile" ""
		cat > $cronfile <<EOF
#!/bin/bash
/usr/local/sbin/btrfs-snp $blockchainvol daily    7 86400 ../$(basename $snapshotsdir)
/usr/local/sbin/btrfs-snp $blockchainvol weekly   4 604800 ../$(basename $snapshotsdir)
/usr/local/sbin/btrfs-snp $blockchainvol monthly 12 2592000 ../$(basename $snapshotsdir)
EOF
		chmod +x $cronfile
	
		# setup .bitcoin data directory
		BITCOIN_DATADIR=$INSTALL_PATH/$BITCOIN_DATADIR_RELATIVE
		display_alert "Creating ${BITCOIN_FILE_PREFIX}bitcoind data directory..." "$BITCOIN_DATADIR"
		if [[ ! -d $BITCOIN_DATADIR ]]; then make_dir $BITCOIN_DATADIR; fi
		if [[ ! -d $BITCOIN_DATADIR/blocks ]]; then sudo -u $BITCOIN_USER ln -s $blockchainvol/blocks $BITCOIN_DATADIR/blocks; fi
		if [[ ! -d $BITCOIN_DATADIR/chainstate ]]; then sudo -u $BITCOIN_USER ln -s $blockchainvol/chainstate $BITCOIN_DATADIR/chainstate; fi
		chown -R $BITCOIN_USER:$BITCOIN_GROUP $BITCOIN_DATADIR
	fi
	
	# download and verify release
	download_and_verify
	
	display_alert "Continuing with installation of:" "$VERSION" ""
	cd $INSTALL_PATH
	display_alert "Installing to:" "$INSTALL_PATH" ""
	local tarcmd="tar -xvf $DOWNLOAD_PATH/$FILENAME"
	display_alert "Extracting release..." "$tarcmd" ""
	local tarout=$($tarcmd)
	local instdir=$(echo $tarout | awk '{print $1}' | sed 's~/$~~')
	
	# copy manual
	display_alert "Installing man pages..." "/usr/local/share/man/" ""
	cp -r $instdir/share/man/* /usr/local/share/man/
	mandb /usr/local/share/man/ 2>&1 | sed "s/^/${SED_INTEND}/"
	
	# copy zHIVERbox bitcoind configuration
	echo ""
	local BITCOIN_CONF=/etc/bitcoin/${BITCOIN_FILE_PREFIX}bitcoin.conf
	display_alert "Apply default zHIVErbox configuration..." "${BITCOIN_CONF}"
	mkdir -p /etc/bitcoin
	install -o root -g root -m 0644 $ZHIVERBOX_HOME/scripts/etc/bitcoin/bitcoin.conf.src $BITCOIN_CONF
	sed -i "s/{{PREFIX}}/${BITCOIN_FILE_PREFIX}/g" $BITCOIN_CONF
	if [[ ${BITCOIN_LAYER1_NETWORK} = testnet ]]; then
		sed -i "s/{{TESTNET}}/testnet=1/" $BITCOIN_CONF
	else
		sed -i "s/{{TESTNET}}/testnet=0/" $BITCOIN_CONF
	fi
	sed -i "s/{{TOR_CONTROL_PORT}}/${TOR_CONTROL_PORT}/g" $BITCOIN_CONF
	
	# setup a dedicated SOCKS5 port for bitcoind with stream isolation
	# see https://tails.boum.org/contribute/design/stream_isolation/
	# bitcoind only connects to 8 peers so using destination address/port isolation seems to be OK
	if ! grep -q 'SocksPort 127.0.0.1:9053' /etc/tor/torrc; then
		display_alert "Creating dedicated Tor SOCKS port 9053 (stream isolation)" "/etc/tor/torrc" "" 
		sed -i '/SocksPort 127.0.0.1:9050/a ## SocksPort for bitcoind\nSocksPort 127.0.0.1:9053 IsolateDestAddr IsolateDestPort' /etc/tor/torrc
		systemctl restart tor
	fi
	
	# Make sure Tor control port is enabled
	#sed -i 's/^#ControlPort 9051/ControlPort 9051/' /etc/tor/torrc
	#systemctl restart tor
	
	# Make sure bitcoind can read Tor control auth cookie
	#usermod --append --groups debian-tor $BITCOIN_USER
	
	# explain zHIVErbox bitcoind configuration
	echo -e \
"The default zHIVErbox configuration for ${BITCOIN_FILE_PREFIX}bitcoind uses Tor for 
both - outbound and inbound connections:
* outbound via dedicated Tor SOCKS5 proxy (127.0.0.1:9053)
* inbound via ephemeral Tor hidden service

This provides you the best privacy, because an observer of your network or
Internet connection won't see you're running a Bitcoin node. All they can see is
that you are using Tor. (Though, a very sophisticated observer might be able to
draw conclusions by analyzing the Tor traffic for specific timing patterns.)
"
	press_any_key
	
	# copy firewall rules
	configure_firewall
	
	# copy daemon and client binary
	local bindir=/usr/local/lib/bitcoin
	local daemonbinname="${BITCOIN_FILE_PREFIX}bitcoind"
	local clibinname="${BITCOIN_FILE_PREFIX}bitcoin-cli"
	display_alert "Installing binaries..." "/usr/local/bin/${daemonbinname} /usr/local/bin/${clibinname}" ""
	mkdir -p $bindir 2>/dev/null
	install -o root -g root -m 0755 $instdir/bin/bitcoind $bindir/${daemonbinname} 2>/dev/null
	ln -sf  $bindir/${daemonbinname} /usr/local/bin/
	install -o root -g root -m 0755 $instdir/bin/bitcoin-cli $bindir/${clibinname} 2>/dev/null
	# create a wrapper script for the client
	rm /usr/local/bin/${clibinname} 2>/dev/null
	cat > /usr/local/bin/${clibinname} << EOF
#!/bin/sh
# Generated by $0
exec $bindir/${clibinname} -conf=${BITCOIN_CONF} -rpccookiefile=/run/${BITCOIN_FILE_PREFIX}bitcoind/authcookie \$1
EOF
	chmod +x /usr/local/bin/${clibinname}
	
	# copy systemd service file
	local servicefile="/etc/systemd/system/${daemonbinname}.service"
	display_alert "Setting up bitcoind as a system service..." "${servicefile}" ""
	install -o root -g root -m 0644 $ZHIVERBOX_HOME/scripts/etc/systemd/system/bitcoind.service.src ${servicefile}
	sed -i "s/{{PREFIX}}/${BITCOIN_FILE_PREFIX}/g" $servicefile
	sed -i "s/{{NETWORK}}/${BITCOIN_LAYER1_NETWORK^^}/g" $servicefile
	sed -i "s~{{DATADIR}}~${datadir}~g" $servicefile
	sed -i "s/{{EXTRA_ARGS_NAME}}/${BITCOIN_FILE_PREFIX^^}BITCOIND_EXTRA_ARGS/g" $servicefile
	sed -i "s/{{BITCOIN_USER}}/${BITCOIN_USER}/g" $servicefile
	sed -i "s/{{TOR_CONTROL_PORT}}/${TOR_CONTROL_PORT}/g" $servicefile
	
	systemctl daemon-reload
	echo -e \
"${BITCOIN_FILE_PREFIX}bitcoind is available as a system service now, but not started automatically on
boot. You can run the following commands to control it:
* ${ORANGE}sudo systemctl start  ${BITCOIN_FILE_PREFIX}bitcoind${NC}
* ${ORANGE}sudo systemctl stop   ${BITCOIN_FILE_PREFIX}bitcoind${NC}
"
	press_any_key
	echo -e \
"If you want ${BITCOIN_FILE_PREFIX}bitcoind to automatically start on every (re-)boot, you can enable
this by runnig the following command:
* ${ORANGE}sudo systemctl enable ${BITCOIN_FILE_PREFIX}bitcoind${NC}
"
	press_any_key
	
	# allow default user control via bitcoin-cli
	local default_user=$(id -nu 1000)
	usermod --append --groups $BITCOIN_GROUP $default_user
#	sudo -u $default_user mkdir /home/$default_user/.${BITCOIN_FILE_PREFIX}bitcoin 2>/dev/null
#	local userconf=/home/$default_user/.${BITCOIN_FILE_PREFIX}bitcoin/bitcoin.conf
#	cat > $userconf << EOF
# Generated by $0
#
# [core]
# Specify the location of the configuration file. To use non-default location, create a default location config file containing this setting.
#conf=/etc/bitcoin/bitcoin.conf

# [rpc]
# Location of the RPC auth cookie
#rpccookiefile=/run/bitcoind/authcookie
#EOF
#	chown $default_user:users $userconf

	display_alert "$VERSION ${BITCOIN_LAYER1_NETWORK^^} installation complete" "" "ext"
	press_any_key
	echo -e \
"${BOLD}Congratulations!${NC} You now have all the software needed to become a ${BOLD}first class
${BITCOIN_LAYER1_NETWORK^^} Bitcoin citizen${NC}. In a few days from now, your zHIVErbox will have fully 
validated your copy of the Bitcoin blockchain. You can check your citizenship 
with the Bitcoin command line interface (${BITCOIN_FILE_PREFIX}bitcoin-cli) at any time:
* ${ORANGE}${BITCOIN_FILE_PREFIX}bitcoin-cli getchaintips${NC}
"
	press_any_key
}

configure_firewall()
{
	local fwrulesdir=/etc/ferm/ferm.d
	display_alert "Configuring ferm firewall for ${BITCOIN_FILE_PREFIX}bitcoind..." "${fwrulesdir}/${BITCOIN_FILE_PREFIX}bitcoin.*" ""
	mkdir -p $fwrulesdir 2>/dev/null
	
	# copy all bitcoin related firewall rules
	local backupdirname=$(echo "_backups/`date +%s`_${BITCOIN_FILE_PREFIX}bitcoin")
	for source in $ZHIVERBOX_HOME/scripts$fwrulesdir/bitcoin.*; do
		sfilename=$(basename $source)
		tfilename=${BITCOIN_FILE_PREFIX}${sfilename}
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
			sed -i "s/{{PREFIX}}/${BITCOIN_FILE_PREFIX}/g" $target
			sed -i "s/{{BITCOIN_USER}}/${BITCOIN_USER}/" $target
			sed -i "s/{{BITCOIN_CONTROL_PORT}}/${BITCOIN_CONTROL_PORT}/" $target
			sed -i "s/{{BITCOIN_DEFAULT_PORT}}/${BITCOIN_DEFAULT_PORT}/" $target
			sed -i "s/{{TOR_CONTROL_PORT}}/${TOR_CONTROL_PORT}/" $target
			
			# rename the target to strip the .src extension
			mv $target $(echo "$target" | sed 's~.src$~~')
		fi
	done
	
	display_alert "Restarting ferm firewall..." "systemctl restart ferm" ""
	systemctl restart ferm
}

# https://en.bitcoin.it/wiki/Data_directory#blocks_subdirectory
preload_blockchain()
{
	display_alert "Preloading a copy of the ${BITCOIN_LAYER1_NETWORK^^} Bitcoin blockchain database" "" "todo"
	echo -e \
"You could start the ${BITCOIN_FILE_PREFIX}bitcoind daemon now and it would start syncing 
the Bitcoin ${BITCOIN_LAYER1_NETWORK^^} blockchain. However, the default zHIVErbox setup is that 
${BITCOIN_FILE_PREFIX}bitcoind only connects via Tor, which will take quite a couple 
of days to download several hundred GB. If you have an existing copy of the 
Bitcoin ${BITCOIN_LAYER1_NETWORK^^} blockchain, you can copy it to the zHIVEbox now. E.g. 
via USB or SSH. This way, you only have to do a full reindex, which is faster.
"
	read -p "$UINPRFX Do you have an existing copy of the ${BITCOIN_LAYER1_NETWORK^^} blockchain? (y/n) [default: no] " choice
	case "$choice" in 
	  y|Y|yes|YES ) PRELOAD_BLOCKCHAIN=yes;;
	  n|N|no|NO ) echo "";;
	esac
	
	if [[ $PRELOAD_BLOCKCHAIN == "yes" ]]; then
	
		done=0
		while : ; do
			display_alert "How do you want to provide the blockchain copy?" "" ""
			local options=( "USB" "SSH")
			if [[ $HAS_IPFS ]]; then
				options+=("IPFS")
			fi
			
			PS3="> Select number: " 
			select option in ${options[@]};
			do
				case $option in
					USB ) select_blocksource_usb; retval=$?; break;;
					SSH ) rsync_blocksource_ssh; retval=$?; break;;
					IPFS ) select_blocksource_ipfs; retval=$?; break;;
				esac
			done
		
			if [[ $retval != 0 ]]; then
				# try again?
				read -p "$UINPRFX Do you want to try again? (y/n) [default: yes] " choice
				case "$choice" in 
				  y|Y|yes|YES ) echo "";; # repeat the while loop
				  n|N|no|NO ) return 1;; # abort preloading blockchain copy
				esac
			else		
				break; # exit the while loop an continue
			fi
		done
		
		# Tell bitcoind to reindex next time it is started via environment variable
		# the '-reindex' argument should be only used once, else bitcoind will start re-indexing again and again
		# there's no simpler way, because we use systemd.
		# Additionally increase '-dbcache' to 1.5GB to speedup syncing (Odroid HC1 has 2GB)
		display_alert "Once copying the blockchain backup is complete enable re-indexing and start bitcoind" "" "todo"
		echo -e \
"The current zHIVErbox hardware (Odroid HC1/HC2) can validate approx. 0.5 blocks
per second. The limitation seems to be the available RAM (2GB) which is not 
enough to fit all unspent transactions (UTXO) and do fast validation.
Thererfore you will be in sync with the end of the Blockchain
(chain tip) in a week.
"
		echo -e "Manually run the following commands on your zHIVErbox:\n"
		press_any_key

		echo -e \
"1. Enable re-indexing:                         
${ORANGE}sudo systemctl set-environment ${BITCOIN_FILE_PREFIX^^}BITCOIND_EXTRA_ARGS='-reindex -dbcache=1500'${NC}

2. Start Bitcoin Core:
${ORANGE}sudo systemctl start ${BITCOIN_FILE_PREFIX}bitcoind${NC}

3. Disable re-indexing:
${ORANGE}sudo systemctl set-environment ${BITCOIN_FILE_PREFIX^^}BITCOIND_EXTRA_ARGS='-dbcache=1500'${NC}
"
		display_alert "It's crucial that you immediately unset the '-reindex' flag from the ${BITCOIN_FILE_PREFIX^^}BITCOIND_EXTRA_ARGS environment varilable again!" "" "wrn"
		display_alert "Else re-indexing will start again and again from the beginning every time ${BITCOIN_FILE_PREFIX}bitcoind starts." "" "wrn"
		echo ""
		press_any_key
		display_alert "To launch ${BITCOIN_FILE_PREFIX}bitcoind automatically with every (re-)boot:" "sudo systemctl enable ${BITCOIN_FILE_PREFIX}bitcoind" "todo"
		press_any_key 
		display_alert "To check the current status of your ${BITCOIN_LAYER1_NETWORK^^} blockchain copy:" "${BITCOIN_FILE_PREFIX}bitcoin-cli getchaintips" ""
		echo ""
		press_any_key
	fi
	
}

select_blocksource_usb()
{
	echo ""
	echo "Please connect the USB disk containing the ${BITCOIN_LAYER1_NETWORK^^} blockchain copy to the zHIVErbox now!"
	press_any_key
	# usually usb disk should be on /dev/sdb1
	local lsblkout=$(lsblk /dev/sdb1)
	if [[ -n $lsblkout ]]; then
		local mntusb=/media/usb/
		mkdir -p $mntusb 2>/dev/null
		mount /dev/sdb1 $mntusb 2>/dev/null
		if cat /proc/mounts | grep -q /dev/sdb1; then
			display_alert "Successfuly mounted USB disk" "mount /dev/sdb1 $mntusb" "ext"
			
			# ask user to navigate to blockchain backup
			local directory=$mntusb
			while [[ -z $blocksdir ]]; do
			
				# test if selected dir has the blocks dir
				if [[ -d ${directory}${blocks} ]]; then
					# does it contain blk*.dat files
					if ls ${directory}blocks | grep -q 'blk.*\.dat'; then
						blocksdir=${directory}blocks
						break
					fi
				fi
				
				# test if selected dir contains blk*.dat files
				if ls $directory | grep -q 'blk.*\.dat'; then
					blocksdir=$directory
					break
				fi
			
				echo -e "\n${MAGENTA}Please navigate to ${BITCOIN_LAYER1_NETWORK^^} blockchain backup directory!${NC}"
				echo -e "$directory"
				local subdirs=$(ls -d $directory*/)
				local parentdir=$(dirname $directory)
				[[ ! $parentdir =~ /$ ]] && parentdir="$parentdir/"
				if [[ $directory != "/" ]]; then
					subdirs=$(echo -e "$subdirs\n$parentdir")
				fi
				PS3="> Select number: "
				select subdir in $subdirs;
				do
					if ls $subdir | grep -q blk.*\.dat; then
						blocksdir=$subdir
					else
						directory=$subdir
					fi
					break
				done
			done
			
			display_alert "Found blockchain backup directory at" "$blocksdir" "ext"
			rsync_blocksource_usb $(dirname $blocksdir)
		else
			display_alert "Your USB disk could not be automatically mounted. Here are manual instructions." "" "err"
		fi
	else
		display_alert "Your USB disk could not be automatically mounted. Here are manual instructions." "" "err" 
	fi
	
	return 0
}

rsync_blocksource_usb()
{
	local blocksource=$1
	display_alert "Size of your blockchain copy:" "$(du -sh $blocksource |  awk '{print $1}') " ""
	echo -e \
"It might take an hour or more to copy all of this. Since this is a long running
process, there's a chance your SSH connection breaks in between and this 
installer is interrupted. Therefore we just show you the command you can run on
your own to copy the blockchain backup. You can re-run this command at any time
without having to start the Bitcoin installer again.
"
	local rsynccmd="rsync -av --include='blocks/***' --include='chainstate/***' --exclude='*' --chown=$BITCOIN_USER:$BITCOIN_GROUP --progress $blocksource/ $INSTALL_PATH/.bitcoin/"
	display_alert "Please run:" "sudo $rsynccmd" "todo"
}

fpsync_blocksource_usb()
{
	local blocksource=$1
	display_alert "Size of your blockchain copy:" "$(du -sh $blocksource |  awk '{print $1}') " ""
	echo -e \
"It might take an hour or more to copy all of this. Since this is a long running
process, there's a chance your SSH connection breaks in between and this 
installer is interrupted. Therefore we just show you the command you can run on
your own to copy the blockchain backup. You can re-run this command at any time
without having to start the Bitcoin installer again.
"
	if [[ -z $(which fpsync) ]]; then
		apt_install_fancy_retry fpart
	fi
	local fpsynccmd="fpsync -vv -S -n 4 -f 1000 -s $((256 * 1024 * 1024)) -o \"-av --include='blocks/***' --include='chainstate/***' --exclude='*' --chown=user:user\" $blocksource/ $INSTALL_PATH/.bitcoin/"
	display_alert "Please run:" "$fpsynccmd" "todo"
}

rsync_blocksource_ssh()
{
	echo ""
	echo -e \
"It will take a couple of hours to copy the Bitcoin blockchain via SSH. There's 
a chance your SSH connection breaks during that time. The following command 
allows you to reconnect and continue copying if this happens, without having to 
start all over again.
"
	press_any_key
	local rsynccmd="rsync -avz --include='blocks/***' --include='chainstate/***' --exclude='*' --chown=$BITCOIN_USER:$BITCOIN_GROUP --progress ./ root@$(hostname):$INSTALL_PATH/.bitcoin/"
	echo -e \
"Change into the Bitcoin data directory (usually ~/.bitcoin) on the remote 
system and run:
${ORANGE}sudo $rsynccmd${NC}
"
	press_any_key
	return 0
}

select_blocksource_ipfs()
{
	echo ""
	echo "Please enter an IPFS path containing a ${BITCOIN_LAYER1_NETWORK^^} blockchain copy."
	echo "The path should point to a directory having the 'blocks' and 'chainstate' directory."
	read -p "$UINPRFX /ipfs/" ipfspath
	
	# simple test if hash contains a copy of the blockchain
	local ipfslsout=$(mktemp)
	timeout $IPFS_TIMEOUT ipfs ls /ipfs/$ipfspath > $ipfslsout
	case $? in 
		124 ) # timeout
  			display_alert "We can't reach any IPFS node sharing the specified path right now!" "/ipfs/$ipfspath" "err";
  			return 1;;
  		0 ) # success
  			echo ""
  			cat $ipfslsout | sed "s/^/${SED_INTEND}/"
  			echo "";;
  		* ) # other errors
  			display_alert "Error accessing the specified IPFS path:" "/ipfs/$ipfspath" "err";
  			return 1;;
  	esac
	
	if cat $ipfslsout | grep -q 'blk.*\.dat'; then
		get_blocksource_ipfs "/ipfs/$ipfspath"
		return 0
	else 
		display_alert "The specified IPFS path doesn't seem to have a bitcoind blockchain copy." "/ipfs/$ipfspath" "err";
		return 1
	fi
}

get_blocksource_ipfs()
{
	local blocksource=$1
	display_alert "Size of your blockchain copy:" "$(( $(ipfs files stat --size $blocksource) / (2**20))) GB" ""
	echo -e \
"It might take several hours to copy all of this. Since this is a long running
process, there's a chance your SSH connection breaks in between and this 
installer is interrupted. Therefore we just show you the command you can run on
your own to copy the blockchain backup. You can re-run this command at any time
without having to start the Bitcoin installer again.
"
	local ipfsgetcmd="ipfs get $blocksource -o $INSTALL_PATH/.bitcoin"
	display_alert "Please run:" "$ipfsgetcmd" "todo"
}

ask_select_network()
{
	echo ""
	display_alert "Which Bitcoin network do you want to connect to?" "" ""
	local options=( "MAINNET" "TESTNET" "BOTH")
	PS3="> Select number: " 
	select option in ${options[@]};
	do
		echo "User selected: $option" >> $ZHIVER_LOG
		case $option in
			MAINNET ) 
				install_bitcoincore;
				preload_blockchain;
				break;;
			TESTNET ) 
				configure_testnet;
				install_bitcoincore;
				break;;
			BOTH )
				# install mainnet
				display_alert "Installing bitcoind MAINNET setup first" "" ""
				install_bitcoincore;
				preload_blockchain;
				
				#install testnet
				display_alert "Installing bitcoind TESTNET setup now" "" ""
				press_any_key
				configure_testnet;
				install_bitcoincore;
				break;;
		esac
	done
	echo ""
}

configure_testnet()
{
	# change variables for testnet
	BITCOIN_USER=test_bitcoind
	BITCOIN_FILE_PREFIX="test_"
	BITCOIN_LAYER1_NETWORK=testnet
	BITCOIN_DEFAULT_PORT=18883
	BITCOIN_CONTROL_PORT=18332
	BITCOIN_DATADIR_RELATIVE=".bitcoin/testnet3"
	
	# dns seeders for testnet
	display_alert "Query IPv4 DNS seeder for TESTNET" "sudo -u nobody dig A seed.tbtc.petertodd.org" ""
	sudo -u nobody dig A seed.tbtc.petertodd.org 1>>$ZHIVER_LOG
	display_alert "Query IPv4 DNS seeder for TESTNET" "sudo -u nobody dig A testnet-seed.bitcoin.jonasschnelli.ch" ""
	sudo -u nobody dig A testnet-seed.bitcoin.jonasschnelli.ch 1>>$ZHIVER_LOG
	display_alert "Query IPv6 DNS seeder for TESTNET" "sudo -u nobody dig AAAA testnet-seed.bitcoin.jonasschnelli.ch" ""
	sudo -u nobody dig AAAA testnet-seed.bitcoin.jonasschnelli.ch 1>>$ZHIVER_LOG
}

# main script
echo ""
display_alert "Installation of Bitcoin Core Full Node on zHIVErbox" "" ""
echo ""

done=0
while : ; do
	ask_install_path "bitcoind" "Bitcoin database" # this sets $INSTALL_PATH (usually /mnt/data/bitcoind)

	INSTALLFS=$(findmnt -n -o fstype -T $(dirname $INSTALL_PATH))
	if [[ ! $INSTALLFS == btrfs ]]; then
		display_alert "You didn't select a btrfs based path" "$INSTALLFS: $INSTALL_PATH" "wrn"
		echo -e \
"We highly recommend that you choose to install the Bitcoin database on a btrfs 
based filesystem. This way we can make use of automated btrfs snapshots of the 
bitcoind blocks and chainstate databases which allow easy rollback in case they 
get corrupted.
"
		read -p "$UINPRFX Do you want to change the installation path? (y/n) " choice
		case "$choice" in 
		  n|N|no|NO ) break;;
		  * ) echo "";; # will repeat the while loop
		esac
	else
		break
	fi
done
display_alert "Installing to:" "$INSTALL_PATH" "ext"
ask_select_network
