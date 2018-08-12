#!/bin/bash

[[ -z ${ZHIVERBOX_HOME} ]] && echo "\$ZHIVERBOX_HOME environment variable not set!" && exit 1
. $ZHIVERBOX_HOME/lib/bash/common.sh

CMD_CURL_TOR="sudo -u nobody curl --socks5-hostname 127.0.0.1:9050"
CMD_WGET_TOR="sudo -u nobody torsocks wget" 

apt_install_fancy_retry()
{
    while ! apt-get -y -q --show-progress -o DPKG::Progress-Fancy=1 install $@
    do
        display_alert "Apt installation failed. Waiting 60s before retrying." "" "err"
        sleep 60
	    apt-get update
    done
}

clone_or_update_from_github()
{
    local name=$1
    local target_path="$SRC_HOME/$name"
    local origin=$2
    if [[ -n $3 ]]; then
    	local branch="--branch $3"
	fi
    
    display_alert "Downloading $name sources from GitHub" "$origin $branch" ""
    echo ""
    
    # use TOR to download from GitHub
    GIT_CMD="sudo -u nobody torsocks git"
    #GIT_CMD="git"
    
    # if source directory doesn't exist yet we have to clone from github first
    
    if [[ ! -d "$target_path/.git/" ]]; then
        display_alert "Clone $name" "$GIT_CMD clone $branch --recursive ${origin}.git $target_path" ""
        echo ""
        mkdir -p $target_path 2>/dev/null
        chown nobody:nogroup $target_path
        $GIT_CMD clone $branch --recursive ${origin}.git $target_path
    fi
    
    local workdir=$(pwd)
    cd $target_path
    display_alert "Target directory:" "$target_path" ""
    
    # change absolute paths in submodules to relative paths
    find -type f -name .git -exec bash -c 'f="{}"; cd $(dirname $f); echo "gitdir: $(realpath --relative-to=. $(cut -d" " -f2 .git))" > .git' \;
    
    # fetch origin for updates
    display_alert "Fetch $name repository updates" "$GIT_CMD fetch" ""
    $GIT_CMD fetch
    
    # local checkout to latest stable version
	latesttag=$(git describe --abbrev=0 --tags 2>/dev/null)
	if [[ -z $branch && -n $latesttag ]]; then
	    display_alert "Switch $name to latest release" "git checkout ${latesttag} && $GIT_CMD submodule update --recursive" ""
	
	    # no torify required for checkout
	    git checkout ${latesttag} && $GIT_CMD submodule update --recursive && export ${name^^}_CHECKOUT_COMPLETE=true
	else
	    display_alert "Pulling updates" "$GIT_CMD pull && $GIT_CMD submodule update --recursive" ""
	    $GIT_CMD pull && $GIT_CMD submodule update --recursive && export ${name^^}_CHECKOUT_COMPLETE=true
	fi

    # TODO: verify sources have not been compromized (man-in-the-middle attack)
    #git verify-tag --raw $(git describe)
    
    # back to working directory
    cd $workdir
    
    echo ""
    display_alert "Download $name from GitHub complete!" "$origin" "ext"
}

ask_install_path()
{
	# usage:
	# $1 install path
	# S2 install description (e.g. "IPFS repository", "Bitcoin database (blockchain)")
	local default_device="/dev/sda"
	local default_mount_point=$(lsblk -l -n -o mountpoint $default_device | grep .)
	local lsblkout=$(lsblk -l -f | grep $default_mount_point)
	local actual_device=$(echo $lsblkout | awk '{print $1}')
	local actual_fstype=$(echo $lsblkout | awk '{print $2}')
	if [[ $actual_fstype = btrfs ]]; then
		# get mount point of default subvolume
		local default_volid=$(btrfs subvolume get-default $default_mount_point | awk '{print $2}')
		default_mount_point=$(mount | grep $actual_device | grep "subvolid=$default_volid" | awk '{print $3}')
	fi
	if [[ -d $default_mount_point ]]; then
    	local default_install_path=$default_mount_point/$1
    else	
    	display_alert "The default storage disk doesn't seem to be mounted!" "$default_device" "err"
    	display_alert "If you know what you're doing you can continue, but it's recommended to" "" "wrn"
    	display_alert "mount the SATA disk first to put the $2 on that disk." "Press CTRL+C to abort" "wrn"
    	local default_ipfs_path=/mnt/data/$1
    fi
    read -p "$UINPRFX Where should the $2 be placed? [default: $default_install_path] " choice
    INSTALL_PATH=${choice:=$default_install_path}
    
    # check if parent directory exists
    if [[ -d $(dirname $INSTALL_PATH) ]]; then
    	export INSTALL_PATH=$INSTALL_PATH
    else
    	display_alert "The parent directory for your $2 path doesn't exist:" "$(dirname $INSTALL_PATH)" "err"
    	display_alert "Please abort and create it manually first or specifiy another path." "Press CTRL+C to abort" "err"
    	ask_install_path $1 "$2"
    fi
}
