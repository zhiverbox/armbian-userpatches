#!/bin/bash

# The zHIVErbox installation scripts may be used according to the
# MIT License EXCEPT for the following conditions:
#   * Running ANY software that forks the
#     Bitcoin consensus (https://bitcoin.org)
#   * If you want to run software like Bcash (Bitcoin Cash),
#     feel free to write your own installation scripts from scratch,
#     but you are not granted permission to use, copy, modify or
#     benefit-from the work of the zHIVErbox authors and contributors.
# We know this sounds arbitrarly and allows for heated discussions,
# but these are simply our terms. We provide our work for free, so
# either accept it or try to create your own stuff.

export SRC_HOME="/tmp/cache/opt/src"
mkdir -p $SRC_HOME

display_alert()
{
    local tmp=""
    [[ -n $2 ]] && tmp="[\e[0;33m $2 \x1B[0m]"

    case $3 in
        err)
        echo -e "[\e[0;31m error \x1B[0m] $1 $tmp"
        ;;

        wrn)
        echo -e "[\e[0;35m warn \x1B[0m] $1 $tmp"
        ;;

        ext)
        echo -e "[\e[0;32m o.k. \x1B[0m] \e[1;32m$1\x1B[0m $tmp"
        ;;

        info)
        echo -e "[\e[0;32m o.k. \x1B[0m] $1 $tmp"
        ;;

        *)
        echo -e "[\e[0;32m .... \x1B[0m] $1 $tmp"
        ;;
    esac
}

install_tor()
{
    echo ""
    display_alert "Install Tor packages" "apt-get -y -q install -t stretch-backports tor torsocks tor-arm apt-transport-tor" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install -t stretch-backports tor torsocks tor-arm apt-transport-tor

    # While apt sends no directly identifying information to mirrors the download of
    # metadata like the translation files as well as individual package names can
    # potentially reveal information about a user an adversary could observe.
    #
    # Therefore, zHIVErbox uses the Debian onion service
    # Debian Project: [Complete List](https://onion.debian.org)
    # [Announcement](https://bits.debian.org/2016/08/debian-and-tor-services-available-as-onion-services.html)
    display_alert "Onionfy Debian apt sources" "/etc/apt/sources.list" ""
    sed -i 's/http:\/\//tor+http:\/\//' /etc/apt/sources.list
    sed -i 's/httpredir.debian.org/vwakviie2ienjx6t.onion/' /etc/apt/sources.list
    sed -i 's/security.debian.org/sgvtcaew4bxjd7ln.onion/' /etc/apt/sources.list
    cat /etc/apt/sources.list
    echo ""

    # no onion service available yet for armbian packages, tor+http must be sufficient for now :(
    display_alert "Torify other apt sources" "/etc/apt/sources.list.d/armbian.list" ""
    sed -i 's/http:\/\//tor+http:\/\//' /etc/apt/sources.list.d/armbian.list
    cat /etc/apt/sources.list.d/armbian.list
    echo ""

    # avoid mistakenly adding new sources without using tor
    display_alert "Disable http(s) without Tor for apt" "/etc/apt/apt.conf" ""
    cat << 'EOF' >> /etc/apt/apt.conf
Dir::Bin::Methods::http "false";
Dir::Bin::Methods::https "false";
EOF
    cat /etc/apt/apt.conf
    echo ""

    # add tor projects repository containing latest Tor releases
    # not needed as long as Debian backports are timely
#    echo \
#"deb tor+http://deb.torproject.org/torproject.org stretch main
#deb-src tor+http://deb.torproject.org/torproject.org stretch main
#" > /etc/apt/sources.list.d/torproject.list

    # refresh apt
    display_alert "Refresh apt repository" "apt-get update" ""
    apt-get update
    echo ""

    # upgrade to latest tor release
    #display_alert "Update Tor packages" "apt-get -y -q install -t stretch-backports tor torsocks tor-arm apt-transport-tor" ""
    #apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install tor torsocks tor-arm apt-transport-tor
}

install_tor_grater()
{
    echo ""
    display_alert "Installing Tor control port filter from Whonix repository..." "" ""
    # install Debian keyring
    display_alert "Installing Debian keyring..." "apt-get -y install debian-keyring" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install debian-keyring

    # import Whonix's signing key
    export GNUPGHOME=/root/.gnupg
    display_alert "Import Whonix signing key..." "https://www.whonix.org/patrick.asc" ""
    torsocks wget https://www.whonix.org/patrick.asc -O - 2>/dev/null | gpg --import
    display_alert "Check Whonix signing key" "gpg --check-sigs 916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA" ""
    gpg --check-sigs 916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA
    display_alert "Add Whonix signing key to apt" "gpg --export 916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA | apt-key add -" ""
    gpg --export 916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA | apt-key add -

    # add Whonix's APT repository.
    display_alert "Add Whonix apt repository" "/etc/apt/sources.list.d/whonix.list" ""
    echo "deb tor+http://deb.whonix.org stretch main" > /etc/apt/sources.list.d/whonix.list

    # install onion-grater
    display_alert "Refresh apt repository" "apt-get update" ""
    apt-get update
    display_alert "Installing Tor control port filter..." "apt-get -y install onion-grater" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install onion-grater

    # Make sure Tor control port is enabled
    display_alert "Enable Tor control port on non-default port 9052" "/etc/tor/torrc" ""
    sed -i 's/^#ControlPort 9051/ControlPort 9052/' /etc/tor/torrc

    # installation complete
    display_alert "Tor control port filter installation complete." "onion-grater" ""
    echo ""
}

setup_tor_enforcement_dns()
{
    # see: https://tails.boum.org/contribute/design/Tor_enforcement/

    echo ""
    display_alert "Install Tor enforcement for DNS" "https://tails.boum.org/contribute/design/Tor_enforcement/" ""

    # configure NetworkManager not to manage resolv.conf at all
    display_alert "Configure NetworkManager not to manage resolv.conf at all" "/etc/NetworkManager/conf.d/dns.conf" ""
    local nmdnsconf=/etc/NetworkManager/conf.d/dns.conf
    mkdir -p $(dirname $nmdnsconf)
    echo -e "[main]\ndns=none" > $nmdnsconf

    # configure dhclient not to manage resolv.conf at all
    display_alert "Configure dhclient not to manage resolv.conf at all" "/etc/dhcp/dhclient-enter-hooks.d/disable_make_resolv_conf" ""
    local dhcconf=/etc/dhcp/dhclient-enter-hooks.d/disable_make_resolv_conf
    mkdir -p $(dirname $dhcconf)
    echo "make_resolv_conf() { : ; }" > $dhcconf
    chmod 755 $dhcconf

    # resolv.conf is configured to point to the Tor DNS resolver
    #display_alert "Point resolv.conf to the local Tor DNS resolver" "/etc/resolv.conf"  ""
    #local resconf=/etc/resolv.conf
    #echo "nameserver 127.0.0.1" > $resconf

    # /etc/resolvconf/resolv.conf.d/head is configured to point to the Tor DNS resolver
    display_alert "Point /etc/resolvconf/resolv.conf.d/head to the local Tor DNS resolver" "/etc/resolvconf/resolv.conf.d/head"  ""
    local resconfhead=/etc/resolvconf/resolv.conf.d/head
    echo "nameserver 127.0.0.1" > $resconfhead
    rm /etc/resolv.conf 2>/dev/null
    ln -s /etc/resolvconf/run/resolv.conf
    resolvconf -u

    # enable DNS, transparent proxy and misc setting
    display_alert "Enable Tor DNS, transparent proxy and misc settings" "/etc/tor/torrc" ""
    cat << 'EOF' >> /etc/tor/torrc

################ zHIVErbox settings ########################################

## Default SocksPort
SocksPort 127.0.0.1:9050 IsolateDestAddr IsolateDestPort
## SocksPort for zHIVErbox-specific applications (e.g. htpdate)
SocksPort 127.0.0.1:9062 IsolateDestAddr IsolateDestPort

## Torified DNS
DNSPort 5353
AutomapHostsOnResolve 1
AutomapHostsSuffixes .exit,.onion

## Transparent proxy
TransPort 9040 IsolateClientAddr IsolateClientProtocol IsolateDestAddr IsolateDestPort

## SSH Hidden Service
HiddenServiceDir /var/lib/tor/ssh_hidden_service/
HiddenServicePort 22 127.0.0.1:22

## Misc
AvoidDiskWrites 1

## Tor 0.3.x logs to syslog by default, which we redirect to the Journal;
## but we have some code (e.g. tordate) that reads Tor's logs and only supports plaintext
## log files at the moment, so let's keep logging to a file.
Log notice file /var/log/tor/log

EOF
    #cat /etc/tor/torrc
    echo ""
}

setup_tor_enforcement_ferm()
{
    echo ""
    display_alert "Install ferm firewall manager" "apt-get -y -q install ferm" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install ferm

    local fermconf=/etc/ferm/ferm.conf
    display_alert "Copy zHIVErbox firewall rules" "$fermconf" ""
    mkdir -p $(dirname $fermconf)
    cp /tmp/overlay$fermconf $fermconf
    mkdir -p /etc/ferm/ferm.d

    # Workaround for broken Path MTU Discovery
    # see https://tails.boum.org/contribute/design/#index32h3
    local pmtudconf="/etc/sysctl.d/pmtud.conf"
    display_alert "Workaround: Enable Packetization Layer Path MTU Discovery" "$pmtudconf" ""
    cp /tmp/overlay$pmtudconf /etc/sysctl.d/

    echo ""
}

setup_time_sync()
{
    # see https://tails.boum.org/contribute/design/Time_syncing/
    echo ""
    display_alert "Install Tails based time syncing" "https://tails.boum.org/contribute/design/Time_syncing/" ""

    local torshell="/usr/local/lib/tor.sh"
    install -o root -g root -m 0744 /tmp/overlay$torshell $torshell

    # install NetworkManager dispatcher
    local nmdisp="/etc/NetworkManager/dispatcher.d/20-time.sh"
    install -o root -g root -m 0744 /tmp/overlay$nmdisp $nmdisp

    # use same user agent as TorBrowser and Tails for htpdate
    CONFFILE='/etc/default/htpdate.user-agent'
    install -o root -g root -m 0644 /dev/null "$CONFFILE"
    echo "HTTP_USER_AGENT=\"Mozilla/5.0 (Windows NT 6.1; rv:52.0) Gecko/20100101 Firefox/52.0\"" \
     > "$CONFFILE"

    # install htpdate service and config
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install \
        libdatetime-perl \
        libdatetime-format-dateparse-perl \
        libgetopt-long-descriptive-perl \
        libipc-system-simple-perl
    local htpdatepoolsconf="/etc/default/htpdate.pools"
    install -o root -g root -m 0644 /tmp/overlay$htpdatepoolsconf $htpdatepoolsconf
    local htpdatebin="/usr/local/sbin/htpdate"
    install -o root -g root -m 0744 /tmp/overlay$htpdatebin $htpdatebin
    local htpdatedservice="/etc/systemd/system/htpdate.service"
    install -o root -g root -m 0644 /tmp/overlay$htpdatedservice $htpdatedservice

    # create htp user (see service file)
    local htp_user="htp"
    local nogroup_id=$(grep -i "^nogroup:" /etc/group | cut -d: -f3)
    adduser --quiet \
            --system \
            --disabled-password \
            --home /run/htpdate \
            --no-create-home \
            --shell /bin/false \
            --gid $nogroup_id \
            $htp_user

    # disable ntpd since we use htpdate instead
    display_alert "Disable ntpd..." "systemctl disable ntpd.service" ""
    systemctl disable ntp.service

    echo ""
}

torify_wget()
{
    # see https://git-tails.immerda.ch/tails/plain/config/chroot_local-hooks/70-wget
    # see https://tor.stackexchange.com/questions/12544/how-can-wget-be-configured-to-work-with-torify-securely

    display_alert "Torifying wget..." "dpkg-divert --add --rename --divert /usr/lib/wget/wget /usr/bin/wget"

    # We don't want the real binary to be in $PATH:
    # Also note that wget uses the executable name in some help/error messages,
    # so wget-real/etc. should be avoided.
    mkdir -p /usr/lib/wget
    dpkg-divert --add --rename --divert /usr/lib/wget/wget /usr/bin/wget

    # We don't want users or other applications using wget directly:
    cat > /usr/bin/wget << 'EOF'
#!/bin/sh
unset http_proxy
unset HTTP_PROXY
unset https_proxy
unset HTTPS_PROXY

exec torsocks /usr/lib/wget/wget --passive-ftp "$@"
EOF

    chmod 755 /usr/bin/wget

}

torify_git()
{
    display_alert "Torifying git..." "git config --system http.proxy 'socks5://127.0.0.1:9050'"
    git config --system http.proxy 'socks5://127.0.0.1:9050'
    
    # git command can (must!) be used WITHOUT torsocks now
    GIT_CMD="git"
}

torify_non_socks()
{
    # not all applications support the socks5 protocol (e.g. npm)
    # we'll offer a local http proxy that can be used by those apps who don't speak socks5
    # see https://medium.com/@jamesjefferyuk/how-to-use-npm-behind-a-socks-proxy-c81d6f51dff8
    display_alert "Installing Torified HTTP Proxy for non-Socks applications..." "apt-get -y -q install polipo"
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install polipo

    cat >> /etc/polipo/config << 'EOF'
socksParentProxy = "127.0.0.1:9050"
socksProxyType = socks5
# listen on localhost (::1) only
proxyAddress = "::1"
proxyPort = 8123
EOF

}

security_hardening()
{
    display_alert "Applying additional zHIVErbox security hardenings..." "" ""

    # disable TCP time stamps
    # see https://tails.boum.org/contribute/design/#index51h3
    local tcptsconf="/etc/sysctl.d/tcp_timestamps.conf"
    display_alert "Disable TCP time stamps" "$tcptsconf" ""
    cp /tmp/overlay$tcptsconf /etc/sysctl.d/

    # disable netfilter's connection tracking helpers
    # see https://tails.boum.org/contribute/design/#index32h3
    local conntracconf="/etc/modprobe.d/no-conntrack-helper.conf"
    display_alert "Disable disable netfilter's connection tracking helpers" "$conntracconf" ""
    cp /tmp/overlay$conntracconf /etc/modprobe.d/

    # systemd-networkd fallbacks to Google's nameservers when no other nameserver
    # is provided by the network configuration. In Stretch, this service is disabled
    # by default, but it feels safer to make this explicit. Besides, it might be
    # that systemd-networkd vs. firewall setup ordering is suboptimal in this respect,
    # so let's avoid any risk of DNS leaks here.
    display_alert "Masking systemd-networkd" "systemctl mask systemd-networkd.service" ""
    systemctl mask systemd-networkd.service

    # Do not run timesyncd: we have our own time synchronization mechanism
    display_alert "Masking systemd-timesyncd" "systemctl mask systemd-timesyncd.service" ""
    systemctl mask systemd-timesyncd.service

    # Do not let pppd-dns manage /etc/resolv.conf
    display_alert "Masking pppd-dns" "systemctl mask pppd-dns.service" ""
    systemctl mask pppd-dns.service

    display_alert "Installing memlockd service" "apt-get -y -q install memlockd" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install memlockd
    local memlockdconf="/etc/memlockd.cfg"
    cp /tmp/overlay$memlockdconf /etc/
    systemctl enable memlockd.service
    echo ""

    display_alert "Installing fail2ban service" "apt-get -y -q install fail2ban" ""
    apt-get -y --show-progress -o DPKG::Progress-Fancy=1 install fail2ban
    systemctl enable fail2ban.service
}

install_btrfs_snp()
{
    echo ""
    local btrfsnpbin="/usr/local/sbin/btrfs-snp"
    display_alert "Install btrfs-snp tool..." "$btrfsnpbin" ""
    install -o root -g root -m 0744 /tmp/overlay$btrfsnpbin $btrfsnpbin
    echo ""
}

clone_or_update_from_github()
{
    local name=$1
    local target_path="$SRC_HOME/$name"
    local origin=$2
    display_alert "Downloading $name sources from GitHub" "$origin" ""
    echo ""

    # use TOR to download from GitHub (see torify_git() function)
    [[ -z $GIT_CMD ]] && GIT_CMD="torsocks git"
   

    # if source directory doesn't exist yet we have to clone from github first
    if [[ ! -d "$target_path/.git/" ]]; then
        display_alert "Clone $name" "$GIT_CMD clone ${origin}.git $target_path" ""
        echo ""
        $GIT_CMD clone ${origin}.git $target_path
    fi

    local workdir=$(pwd)
    cd $target_path
    display_alert "Target directory:" "$target_path" ""

    # fetch origin for updates
    display_alert "Fetch $name repository updates" "$GIT_CMD fetch" ""
    $GIT_CMD fetch

    # local checkout to latest stable version
    latesttag=$(git describe --abbrev=0 --tags)
    display_alert "Switch $name to latest release" "git checkout ${latesttag}" ""

    # no torify required for checkout
    git checkout ${latesttag} && export ${name^^}_CHECKOUT_COMPLETE=true

    # TODO: verify sources have not been compromized (man-in-the-middle attack)
    #git verify-tag --raw $(git describe)

    # back to working directory
    cd $workdir

    echo ""
    display_alert "Download $name from GitHub complete!" "$origin" "ext"
}

install_cjdns()
{
    # TODO: find out why this sometimes hangs at some point and never finishes
    build_cjdns_from_sources

    # install from built sources
    install_cjdns_service /opt/src/cjdns

    # install from pre-compiled sources if above steps hang on your build system
    #install_cjdns_service /tmp/overlay/build/precompiled/cjdns-v20.1-armhf
}

build_cjdns_from_sources()
{
    apt-get -y -q install build-essential python2.7 git
    apt-get -y -q install nodejs
    #apt-get -y -q install libuv0.10 libuv0.10-dev
    #apt-get -y -q install libuv1 libuv1-dev

    while [ ! $CJDNS_CHECKOUT_COMPLETE  ]
    do
        clone_or_update_from_github "cjdns" "https://github.com/cjdelisle/cjdns"
    done

    local workdir=$(pwd)
    # install cjdns according to https://github.com/cjdelisle/cjdns
    cd $SRC_HOME/cjdns
    display_alert "Building cjdns:" "NO_TEST=1 torsocks ./do" ""
    NO_TEST=1 torsocks ./do
    #NO_TEST=1 ./do

    # copy everything to persistent location
    mkdir -p /opt/src 2>/dev/null
    cp -r $SRC_HOME/cjdns /opt/src/

    # back to working directory
    cd $workdir

    display_alert "cjdns built from sources" "COMPLETE" "info"
}

install_cjdns_service()
{
    display_alert "Install cjdns as system service" "BEGIN" ""
    install -o root -g root -m 0755 $1/cjdroute /usr/bin/cjdroute
    display_alert "Copied:" "/usr/bin/cjdroute" "info"

    # copy service files
    install -o root -g root -m 0644 $1/contrib/systemd/cjdns.service /etc/systemd/system/
    display_alert "Copied:" "/etc/systemd/system/cjdns.service" "info"

    install -o root -g root -m 0644 $1/contrib/systemd/cjdns-resume.service /etc/systemd/system/
    display_alert "Copied:" "/etc/systemd/system/cjdns-resume.service" "info"

    # copy zHIVErbox cjdns-dynamic.service file
    local cjdnsdynservice="/etc/systemd/system/cjdns-dynamic.service"
    install -o root -g root -m 0644 /tmp/overlay$cjdnsdynservice $cjdnsdynservice
    display_alert "Copied:" "$cjdnsdynservice" "info"

    # copy cjdns-dynamic.conf example file
    local cjdnsdynconf="/etc/cjdns-dynamic.conf"
    install -o root -g root -m 0644 $1/contrib/python/cjdns-dynamic.conf $cjdnsdynconf
    display_alert "Copied:" "$cjdnsdynconf" "info"

    # add kadnode example dummy
    cat << 'EOF' >> /etc/cjdns-dynamic.conf
# Example for KadNode .p2p names as hostname
#[1fhhjzug91xvbsmksjnlx9cq6n8tzcs6d7fsbdv8j70cktg9nnv0.k]
#hostname: 456a94v74k8e9pfnuhueq3p926u7a3q8dukvck4qaj1p69pvqa9g.p2p
#port: 11921
#password: zyplv05r98mr96wm0ry19tq7u29cql2

EOF

    # create default .cjdnsadmin file for root (needed by cjdns-dynamic.service)
    cat << 'EOF' > /root/.cjdnsadmin
{
    "addr": "127.0.0.1",
    "port": 11234,
    "password": "NONE"
}
EOF

    display_alert "Install cjdns as system service" "COMPLETE" "info"
    echo ""

    # enable system services
    systemctl enable cjdns
    systemctl enable cjdns-resume
    systemctl enable cjdns-dynamic

    echo ""
}

build_install_kadnode_from_sources()
{
    echo ""
    display_alert "Building KadNode package from Github sources" "https://github.com/mwarning/KadNode" "info"
    while [ ! $KADNODE_CHECKOUT_COMPLETE  ]
    do
        clone_or_update_from_github "KadNode" "https://github.com/mwarning/KadNode"
    done

    local workdir=$(pwd)
    # install kadnode according to https://github.com/mwarning/KadNode/blob/master/debian/README.md
    apt-get -y -q install \
                    build-essential devscripts \
                    libmbedtls-dev libnatpmp-dev libminiupnpc-dev \
                    libmbedtls10 fakeroot
    # debhelper >= 11 is only available via stretch-backports
    apt-get -y -q install -t stretch-backports debhelper
    cd $SRC_HOME/KadNode

    # create an unsigned package
    dpkg-buildpackage -b -rfakeroot -us -uc

    display_alert "KadNode build from sources complete" "" "info"
    echo ""

    # install the package
    display_alert "Installing KadNode package" "dpkg -i ../kadnode_*_armhf.deb" "info"
    dpkg -i ../kadnode_*_armhf.deb
    echo ""

    # disable kadnode service (user will be asked to enabled it on first login)
    display_alert "Disabling KadNode service by default" "systemctl disable kadnode" "info"
    systemctl disable kadnode
    systemctl stop kadnode

    # create a system user for kadnode
    KADNODE_USER=kadnode
    KADNODE_HOME=/run/kadnode
    KADNODE_CONFIG=/etc/kadnode/kadnode.conf
    display_alert "Creating system user 'kadnode' ..." "/etc/passwd" ""
    if [[ -z $(getent passwd $KADNODE_USER >/dev/null) ]]; then
        adduser --quiet \
            --system \
            --disabled-password \
            --home $KADNODE_HOME \
            --no-create-home \
            --shell /bin/false \
            --group \
            $KADNODE_USER
    fi

    # add or modify --user argument in kadnode config
    if grep -q '^--user' $KADNODE_CONFIG; then
        sed -i "s/^--user .*$/--user $KADNODE_USER/" $KADNODE_CONFIG
    else
        echo "--user $KADNODE_USER" >> $KADNODE_CONFIG
    fi

    # make /etc/kadnode/peers.txt writeable for system user kadnode
    chown kadnode:kadnode /etc/kadnode/peers.txt
}

make_initramfs_motd()
{
    initrmfs_motd="/etc/initramfs-tools/etc/motd"
    mkdir -p $(dirname $initrmfs_motd)

    zhiverbox_art_main="toilet -f standard -W -F metal zHIVErbox"
    $zhiverbox_art_main > $initrmfs_motd

    # remove last two lines of zHIVErbox logo
    # seems like dropbear motd has a limit and can't handle so much
    sed -i '$d' $initrmfs_motd #remove last line
    sed -i '$d' $initrmfs_motd #remove last line

    # add security disclaimer
    echo -e "\e[1;31m" >> $initrmfs_motd # make red
    toilet -f wideterm -F border " BOOT SYSTEM  -  UNLOCK CRYPTROOT " >> $initrmfs_motd
    echo -e "\e[0;41mREMEMBER:\e[0m Current \e[1mzHIVErbox\e[0m hardware \e[4mlacks SECURE BOOT\e[0m ability!
\e[2mLeft your zHIVErbox unwatched for some time? Verify boot system
externally (via your computer) before typing your passphrase here!\e[0m" >> $initrmfs_motd
    echo -e "\e[0m" >> $initrmfs_motd # reset color
}

debug_make_initramfs_motd()
{
    echo "" && display_alert "Create initramfs motd" "/etc/initramfs-tools/etc/motd" ""

    make_initramfs_motd

    cat /etc/initramfs-tools/etc/motd
}

copy_initramfs_etc_profile()
{
    local etcprofile="/etc/initramfs-tools/etc/profile"
    install -o root -g root -m 0644 -D /tmp/overlay/build$etcprofile $etcprofile
}

copy_initramfs_tools()
{
    local hooksdir="/etc/initramfs-tools/hooks"
    install -o root -g root -m 0755 /tmp/overlay/build/$hooksdir/zhiverbox $hooksdir/
    #local INITTOPDIR="/etc/initramfs-tools/scripts/init-top"
    #install -o root -g root -m 0755 /tmp/overlay$INITTOPDIR/hostname $INITTOPDIR/
}

install_zhiverbox_scripts()
{
    apt-get -y -q install dc

    mkdir -p /opt/zhiverbox
    cp -r /tmp/overlay/opt/zhiverbox /opt/
}

install_post_user_setup_customization()
{

    local script=/opt/zhiverbox/scripts/etc/profile.d/z_10_post_user_setup_customization.sh
    echo "" && display_alert "Install post-user-setup script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script

    # activate execution of script on first login
    mkdir /etc/zhiverbox 2>/dev/null
    touch /etc/zhiverbox/.post_user_setup
}

install_disk_setup_assistance()
{
    local script=/opt/zhiverbox/scripts/etc/profile.d/z_20_check_hard_disk_setup.sh
    echo "" && display_alert "Install hard disk assistance script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script
}

install_ipfs_setup_assistance()
{
    local script=/opt/zhiverbox/scripts/etc/profile.d/z_30_check_ipfs_setup.sh
    echo "" && display_alert "Install IPFS setup assistance script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script
}

install_kadnode_setup_assistance()
{
    local script=/opt/zhiverbox/scripts/etc/profile.d/z_31_check_kadnode_setup.sh
    echo "" && display_alert "Install KadNode setup assistance script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script
}

install_bitcoind_setup_assistance()
{
    local script=/opt/zhiverbox/scripts/etc/profile.d/z_50_check_bitcoind_setup.sh
    echo "" && display_alert "Install Bitcoin Core setup assistance script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script
}

install_btcrpcexplorer_setup_assistance()
{
    local script=/opt/zhiverbox/scripts/etc/profile.d/z_51_check_btc-rpc-explorer.sh
    echo "" && display_alert "Install BTC RPC Explorer setup assistance script" "$script" ""
    ln -s $script /etc/profile.d/
    chmod +x $script
}

motd_change_10_header()
{
    local motdfile="/etc/update-motd.d/10-armbian-header"
    echo "" && display_alert "Changing motd header" "$motdfile" ""

    local zhiverbox_art_main="toilet -f standard -W -F metal zHIVErbox"
    local zhiverbox_art_sub="toilet -f wideterm -F border ' Unfairly secure. Unfairly cheap. '"
    #local zhiverbox_art="toilet -f standard -W -F metal zHIVErbox && toilet -f wideterm -F border Unfairly secure. ' ' Unfairly cheap."

    # replace lines with $BOARD_NAME TERM
    sed -i "/if.*\[.*\$(echo.*\$BOARD_NAME/,/fi/c TERM=linux $zhiverbox_art_main && $zhiverbox_art_sub" $motdfile
    cat $motdfile
}

motd_change_30_sysinfo()
{
    local motdfile="/etc/update-motd.d/30-armbian-sysinfo"
    echo "" && display_alert "Changing motd sysinfo" "$motdfile" ""
    
    # modify output
    local oldipline="printf \"IP:            \""
    local newipline="printf \"Local IP:      \""
    sed -i "s/$oldipline/$newipline/" $motdfile
    
    # modify storage
    sed -i "s/storage=\/dev\/sda1/storage=\/dev\/mapper\/cryptdata/" $motdfile

    cat $motdfile
}

motd_add_31_dnets()
{
    local motdfile="/etc/update-motd.d/31-zhiverbox-dnets"
    echo "" && display_alert "Adding motd dnets" "$motdfile" ""
    # setup requirements

    # tor info requirements
    local tor_info_script=/opt/zhiverbox/scripts/cron/check_tor_info.sh
    chmod +x $tor_info_script
    cp /opt/zhiverbox/scripts/etc/systemd/system/tor-motd-info.* /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable tor-motd-info.path

    # cjdns info requirements
    apt-get -y -q install jq

    # hyperboria info requirements
    local hyperboria_info_script=/opt/zhiverbox/scripts/cron/check_hyperboria_connection.sh
    chmod +x $hyperboria_info_script
    # run every 30 minutes
    { crontab -l; echo "*/30 * * * * $hyperboria_info_script"; } | crontab -

    # activate the actual motd script
    local script=/opt/zhiverbox/scripts/$motdfile
    ln -s $script /etc/update-motd.d/
    chmod +x $script

    cat $motdfile
}

motd_change_35_tips()
{
    local motdfile="/etc/update-motd.d/35-armbian-tips"
    echo "" && display_alert "Changing motd sysinfo" "$motdfile" ""
    echo "DON'T TRUST. VERIFY!" >> /etc/update-motd.d/quotes.txt
}

motd_add_36_donations()
{
    local motdfile="/etc/update-motd.d/36-zhiverbox-donations"
    echo "" && display_alert "Adding motd donations" "$motdfile" ""
    local script=/opt/zhiverbox/scripts/$motdfile
    ln -s $script /etc/update-motd.d/
    chmod +x $script

    cat $motdfile
}

# enable save hard disk parking on shutdown
# https://wiki.odroid.com/odroid-xu4/troubleshooting/shutdown_script
safe_hard_disk_parking_on_shutdown()
{
    echo "" && display_alert "Installing safe hard disk parking fix" "https://wiki.odroid.com/odroid-xu4/troubleshooting/shutdown_script" ""
    apt-get -y -q install hdparm mdadm
    sudo install -o root -g root -m 0755 /tmp/overlay/lib/systemd/system-shutdown/odroid.shutdown /lib/systemd/system-shutdown/odroid.shutdown
}
