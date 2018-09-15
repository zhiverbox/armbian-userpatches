#!/bin/bash

. /opt/zhiverbox/lib/bash/common.sh

# LUKS key-slot used by zHIVErbox for auto-unlock (crypttab) key files
# use key-slot 7 across all zhiverbox installations
AUTOKEYSLOT=7

# get the path to this script
SRC=${BASH_SOURCE[0]}

if [[ $EUID != 0 ]]; then
    display_alert "Hard disk setup requires admin priviliges, trying to use sudo" "" "wrn"
    sudo bash "$SRC" "$@"
    exit $?
fi

# default mount options valid for all file system types
FSOPTS="defaults,noatime,nodiratime"

DISK=$1
PART=${DISK}1
NO_REMIND_SETUP_FILE=/etc/zhiverbox/.no_remind_hard_disk_setup

# exit if one tries to setup the SD-Card (cryptroot) with this script
if [[ $DISK =~ "/dev/mmcblk.*" ]]; then
    display_alert "DON'T USE THIS SCRIPT WITH THE SD-CARD!" "" "err"
    exit 1
fi

check_part_is_luks()
{
    local part_type=$(blkid $PART | awk ' { print $3 } ' | sed 's/.*="//' | sed 's/"//')
    [[ $part_type == "crypto_LUKS" ]] && echo true || echo false
}

ask_mount_or_reformat()
{
    echo ""
    display_alert "The hard disk already contains a LUKS encrypted container." "blkid $DISK" "wrn"
    display_alert "> $(blkid $PART | awk '{ print $1 "\t" $2 "\t" $3 }')" "" "indent"
    display_alert "Maybe from a previous zHIVErbox installation?!" "" ""
    echo ""
    echo "What do you want to do?"
    PS3="> Select number: "
    select action in \
    'Use it  : Just use the disk as it is (mount).'\
    'Wipe it : Securely erase all data and setup again.'\
    'Opt out : I'\''ll handle it by myself manually. Please don'\''t remind me again!'\
    'Postpone: Do nothing right now but remind me later!';
    do
        case $REPLY in
            1) echo "" && unlock_part;
               break;;
            2) do_format_disk;
               break;;
            3) echo "" && opt_out;
               break;;
            4) echo "" && exit 1;
               break;;
        esac
    done
}

ask_mount_name()
{
    local default_name="data"
    read -p "$UINPRFX Assign a name to the disk (mount point): [default: $default_name] " choice
    mount_name=${choice:=data}
    mapper_name="crypt$mount_name"
}

unlock_part()
{
    ask_mount_name
    echo "$mapper_name : $mount_name"
    cryptsetup luksOpen $PART $mapper_name
    dmsetup info -c
    if [[ -b /dev/mapper/$mapper_name ]]; then
        FSTYPE=$(blkid -s TYPE -o value /dev/mapper/${mapper_name})
        mkdir -p /mnt/$mount_name
        case $FSTYPE in
            btrfs )
                # mount default subvolume on $mount_name
                umount /mnt/$mount_name 2>/dev/null
                mount -o "$FSOPTS,compress-force=lzo" /dev/mapper/$mapper_name /mnt/$mount_name;
                # mount root volume on $MOUNT_BTRFSROOT/$mapper_name
                umount $MOUNT_BTRFSROOT/$mapper_name 2>/dev/null
                mount -o "$FSOPTS,compress-force=lzo,subvolid=0,x-mount.mkdir" /dev/mapper/$mapper_name $MOUNT_BTRFSROOT/$mapper_name;;
            * )
                umount /mnt/$mount_name 2>/dev/null
                mount -o "$FSOPTS,x-mount.mkdir" /dev/mapper/$mapper_name /mnt/$mount_name;;
        esac
    else
        echo "Could not unlock hard disk. You may consider reformating the disk if the problem persists."
        ask_mount_or_reformat
    fi

    ask_setup_auto_unlock

    do_final_check

    # all done
    exit 0
}

do_format_disk()
{
    # check if there are any partitons
    [[ ! -z $(partx -sg $DISK) ]] && ask_confirm_reformat

    # erase the disk
    do_secure_erase

    # assign name
    ask_mount_name

    # create a partition
    make_partition

    # create luks container
    do_create_luks

    # make btrfs filesystem
    make_filesystem

    # setup auto unlock
    ask_setup_auto_unlock

    # final check
    do_final_check
}

ask_confirm_reformat()
{
    display_alert "CAUTION: This will erase all data on the hard disk. Are you sure?" "" "wrn"
    display_alert "YOU WILL LOOSE ALL DATA ON THE HARD DISK!!!" "$DISK" "wrn"
    read -p "Type 'erase' in UPPERCASE to continue: " choice
    case "$choice" in
      ERASE ) echo ""; break;;
      n|N|no|NO) echo "" && ask_mount_or_reformat;;
      * ) ask_confirm_reformat;;
    esac
}

do_secure_erase()
{
    echo ""
    display_alert "Using shred to securely delete disk." "shred -n1 -v $DISK" ""
    display_alert "This will fill the whole disk with random data and takes quite some time." "" "indent"
    display_alert "IT'S NOT RECOMMENDED TO SKIP THIS!" "" "indent"
    read -p "$UINPRFX Type 'skip' in UPPERCASE to skip shredding or just hit RETURN to continue: " choice
    case "$choice" in
      SKIP ) echo "" && return;;
      * ) ;;
    esac
    display_alert "Start filling hard disk with random data. This will take some time..." "shred -n1 -v $DISK" ""
    shred -n1 -v $DISK
    display_alert "Filling hard disk with random data. " "COMPLETED" "ext"
}

do_create_luks()
{
    # make sure we have no conflicting mapper mounted
    umount /dev/mapper/$mapper_name 2>/dev/null
    cryptsetup luksClose $mapper_name 2>/dev/null

    display_alert "Encrypting disk with LUKS" " cryptsetup luksFormat -v -q -h sha512 -s 512 --key-file=$TMP_PASS $PART" ""
    echo ""
    do_create_passphrase
    cryptsetup luksFormat -v -q -h sha512 -s 512 --key-file=$TMP_PASS $PART
    echo ""
    display_alert "The $mount_name disk is now ecrypted with a new unique volume key!" "" "ext"
    echo ""
    display_alert "The passphrase to manually unlock the disk is:" "" ""
    echo ""
    echo -e -n "\e[7m" | sed 's/^/         /'
    cat $TMP_PASS
    echo -e -n "\e[27m"
    echo ""
    echo ""
    press_any_key
    display_alert "Make sure to \e[0;31mwrite down this passphrase\x1B[0m or use a secure Password Manager!" "" "wrn"
    display_alert "You usually don't need to enter this passphrase. Only if you reinstall the system or ever want to plug this disk to another computer." "" "indent"
    echo ""
    press_any_key
    display_alert "If you loose this passphrase and your SD-Card breaks or gets lost, your hard disk cannot be unlocked anymore!" "" "wrn"
    echo ""
    press_any_key
    display_alert "Let's test your passphrase before we continue!" "" ""
    cryptsetup luksOpen $PART $mapper_name
}

do_create_passphrase()
{
    # create a 20 character long random passphrase
    TMP_PASS=$(mktemp -p /dev/shm)
    local rand=$(dd if=/dev/urandom bs=4096 count=1 2>/dev/null | sha512sum | awk '{ print $1 }')
    encodeBase58 $rand | cut -c1-20 | tr -d " \t\n\r" > $TMP_PASS
}

make_partition()
{
    echo ""

    # make partition table
    display_alert "Creating a new partition table:" "parted -s $DISK -- mklabel gpt" "info"
    parted -s $DISK -- mklabel gpt

    # create one partition
    display_alert "Creating a partition:" "parted -s $DISK --align optimal -- mkpart primary btrfs ${offset}s 100%" "info"
    parted -s $DISK --align optimal -- mkpart primary btrfs 0% 100%
}

make_filesystem()
{
    FSTYPE=btrfs
    echo ""
    display_alert "Creating $FSTYPE filesystem on $mount_name disk:" "mkfs.$FSTYPE -f /dev/mapper/${mapper_name}" ""
    mkfs.$FSTYPE -f -L ${mapper_name}-$(hostname) /dev/mapper/${mapper_name}

    # mount under /run/.btrfsroot/ first
    mount -o "$FSOPTS,compress-force=lzo,subvolid=0,x-mount.mkdir" /dev/mapper/$mapper_name $MOUNT_BTRFSROOT/$mapper_name

    # create a subvolume
    display_alert "Creating @${mount_name} subvolume on ${mapper_name} disk:" "btrfs subvolume create $MOUNT_BTRFSROOT/${mapper_name}/@${mount_name}" ""
    btrfs subvolume create $MOUNT_BTRFSROOT/${mapper_name}/@${mount_name}

    # make default subvolume
    local subvolid=$(btrfs subvolume list $MOUNT_BTRFSROOT/${mapper_name} | grep @${mount_name} | awk '{print $2}')
    btrfs subvolume set-default $subvolid $MOUNT_BTRFSROOT/${mapper_name}
}

ask_setup_auto_unlock()
{
    echo ""
    display_alert "Automatically unlock this hard drive ($PART) on every system start?" "" "todo"
    read -p "$UINPRFX Enable auto-unlock (y/n)? [default: yes] " choice
    case "$choice" in
      n|N|no|NO ) AUTO_UNLOCK=false;;
      * ) AUTO_UNLOCK=true;;
    esac

    if [[ $AUTO_UNLOCK = true ]]; then
        setup_auto_unlock
        # unmount and test mount via fstab
        umount /mnt/$mount_name 2>/dev/null
        mkdir -p /mnt/${mount_name}
        mount /mnt/$mount_name
    fi
}

setup_auto_unlock()
{
    # put key in hidden directory to avoid accidential deletion
    autokeyfile="/root/.keys/luks-${mapper_name}.key"

    display_alert "Generating a 512 bit keyfile using kernel entropy (randomness)..." "$autokeyfile" ""

    mkdir -p $(dirname $autokeyfile)
    chmod 700 $(dirname $autokeyfile)
    touch $autokeyfile
    chmod 400 $autokeyfile
    dd if=/dev/urandom bs=4096 count=1 2>/dev/null | sha512sum | awk '{ print $1 }' > $autokeyfile

    # add and enable the autokeyfile in LUKS
    if [[ -z $TMP_PASS ]]; then
        display_alert "Adding keyfile to LUKS container requires disk passphrase!" "cryptsetup luksAddKey --key-slot $AUTOKEYSLOT $PART $autokeyfile" ""
        # luksAddKey doesn't automatically repeat (--tries) if the passphrase doesn't match
        # so we have to take care of that
        local success=false
        local errorfile=$(mktemp -p /dev/shm)
        while [[ $success = false ]]; do
            cryptsetup luksAddKey --key-slot $AUTOKEYSLOT $PART $autokeyfile 2>$errorfile
            if [[ -s $errorfile ]]; then
                cat $errorfile
                echo ""
                if grep -q "Key slot $AUTOKEYSLOT is full, please select another one." $errorfile; then
                    display_alert "LUKS key slot $AUTOKEYSLOT is already used." "$PART" "wrn"
                    echo -e \
"zHIVErbox uses key slot $AUTOKEYSLOT for the auto-unlock keyfile. The above warning means
slot $AUTOKEYSLOT was likely used by a previous zHIVERbox installation. If true, it should
not be needed anymore and can be emptied so we can reuse it for the current
installation."
                    done=0
                    while : ; do
                        read -p "$UINPRFX Empty key slot $AUTOKEYSLOT? (y/n) " choice
                        case "$choice" in
                          y|Y|yes|YES )
                              display_alert "Trying to empty key-slot 7 ..." "cryptsetup luksKillSlot $PART $AUTOKEYSLOT" "";
                              cryptsetup luksKillSlot $PART $AUTOKEYSLOT && echo "Key slot $AUTOKEYSLOT was emptied.";
                              display_alert "Retrying to add auto-unlock keyfile..." "cryptsetup luksAddKey --key-slot $AUTOKEYSLOT $PART $autokeyfile" "" && break;;
                          n|N|no|NO ) echo "Aborting. Please setup auto-unlock manually!" && exit 0;;
                          * ) echo "";; # will repeat the while loop
                        esac
                    done

                fi
            else
                success=true
            fi
        done

    else
        cryptsetup luksAddKey --key-slot $AUTOKEYSLOT --key-file=$TMP_PASS $PART $autokeyfile
    fi

    UUID="$(blkid -s UUID -o value $PART)"

    # add autokeyfile to crypttab
    add_modify_crypttab

    # mount crypt device via fstab
    add_modify_fstab

    # modify /etc/update-motd.d/30-armbian-sysinfo
    modify_motd_sysinfo
}

add_modify_crypttab()
{
    echo ""
    local target_file="/etc/crypttab"
    local line_entry="${mapper_name} UUID=$UUID $autokeyfile luks,keyslot=$AUTOKEYSLOT"

    local existing_mapper_name=$(grep $mapper_name $target_file)
    if [[ -z $existing_mapper_name ]]; then
        # partition was never setup before in crypttab
        # just add it
        echo $line_entry >> $target_file
        display_alert "Added keyfile to:" "$target_file" "info"
    else
        # there's a previous mapper entry, modify it
        sed -i "/^${mapper_name}/c\\$line_entry" $target_file
        display_alert "Changed the keyfile in:" "$target_file" "info"
    fi
    cat /etc/crypttab
}

add_modify_fstab()
{
    echo ""
    local target_file="/etc/fstab"
    case $FSTYPE in
        btrfs)
            local btrfsopts="$FSOPTS,compress=lzo"
            # check if we have a dedicated subvolume with the same name
            subvol=$(btrfs subvolume list $MOUNT_BTRFSROOT/${mapper_name} | grep "path @${mount_name}$");
            if [[ -n $subvol ]]; then
                # we have a dedicated subvolume
                fsopts1="$btrfsopts,subvol=@${mount_name} 0 0"; #fs_passno should be 0 for btrfs
                fsopts2="$btrfsopts,subvolid=0,x-mount.mkdir 0 0"; #fs_passno should be 0 for btrfs
            else
                # mount default subvolume
                fsopts1="$btrfsopts 0 0"; #fs_passno should be 0 for btrfs
                fsopts2="$btrfsopts,subvolid=0,x-mount.mkdir 0 0"; #fs_passno should be 0 for btrfs
            fi
            ;;
        *)
            fsopts1="$FSOPTS 0 2";; #fs_passno should be 2 for traditional fs
    esac

    mkdir -p /mnt/${mount_name}
    local line_entry1="/dev/mapper/${mapper_name} /mnt/${mount_name} $FSTYPE $fsopts1"
    if [[ $FSTYPE = btrfs ]]; then
        line_entry2="/dev/mapper/${mapper_name} $MOUNT_BTRFSROOT/${mapper_name} $FSTYPE $fsopts2"
    fi

    local existing_mapper_name=$(grep ${mapper_name} $target_file)
    if [[ -n $existing_mapper_name ]]; then
        # crypt device was setup before in fstab
        # just delete it
         sed -i "~${mapper_name}~d" $target_file
         display_alert "Removed old crypt device references in:" "$target_file" "info"
       fi

       # add the crypt device mounts at the end
       echo $line_entry1 >> $target_file
    [[ -n line_entry2 ]] && echo $line_entry2 >> $target_file
    display_alert "Added crypt device to:" "$target_file" "info"

    cat $target_file
}

modify_motd_sysinfo()
{
    echo ""
    local target_file="/etc/update-motd.d/30-armbian-sysinfo"
    sed -i "/^storage=/c\storage=/dev/mapper/${mapper_name}" $target_file
    display_alert "Changed storage device to monitor in:" "$target_file" "info"
}

do_final_check()
{
    echo ""
    display_alert "Final check:" "df -h /mnt/$mount_name" ""
    local result=$(cat /proc/mounts | grep /mnt/$mount_name)

    if [[ ! -z $result ]]; then
        df -h /mnt/$mount_name
        # set the label of the filesystem to include the hostname
        btrfs filesystem label /mnt/$mount_name ${mapper_name}-$(hostname)
        echo ""
        display_alert "The hard disk was successfully setup and is ready for use:" "/mnt/$mount_name" "ext"
        press_any_key

        # relocate /var
        if [[ $FSTYPE = btrfs ]]; then
            ask_relocate_vardir
        fi
    else
        echo ""
        display_alert "The hard disk was not mounted. Please check the logs." "$ZHIVER_LOG" "err"
        exit 1
    fi

}

opt_out()
{
    display_alert "Opting out of hard disk setup. We'll never remind you again. :" "touch $NO_REMIND_SETUP_FILE" "info"
    mkdir -p $(dirname $NO_REMIND_SETUP_FILE)
    touch $NO_REMIND_SETUP_FILE
    exit 0
}

ask_relocate_vardir()
{
    display_alert "Relocate /var directory to hard disk" "" "todo"
    press_any_key
    echo -e \
"SD-Cards were not designed to drive operatings systems, hence they will wear down
quite fast due to many frequent writes. But as zHIVErbox has a hard disk, we can
counter that by relocating directories with frequent writes (mainly the /var
directory having /var/log, /var/cache, /var/swap, /var/tmp, ...) to the hard
disk. The only exception is /var/lib, which should stay on the SD-Card, so
zHIVErbox can still be used without issues even when the hard disk is unplugged.
"
    read -p "$UINPRFX Relocate /var to hard disk (y/n): [default: yes] " choice
    case "$choice" in
      n|N|no|NO) echo "";;
      * ) relocate_vardir_btrfs;;
    esac
}

relocate_vardir_btrfs()
{
    display_alert "Relocating btrfs @var subvolume to hard disk..." "" ""
    local destination=$MOUNT_BTRFSROOT/${mapper_name}/@var
    local snapsource=$MOUNT_BTRFSROOT/cryptroot/@var
    local snapshotreldir=../.snapshots
    local snapshotdir=$snapsource/$snapshotreldir
    local snapcmd="btrfs-snp $snapsource @var 0 0 $snapshotreldir"
    display_alert "Creating btrfs snapshot..." "$snapcmd" ""
    snapout=$($snapcmd 2>&1)
    echo $snapout
    local snapshotname=$(echo $snapout | grep 'snapshot .* generated' | sed "s/^.*' snapshot @var/@var/" | awk '{print $1}')
    display_alert "Created snapshot of current @var subvolume" "$snapshotname" "info"
    if [[ -d $snapshotdir/${snapshotname:=UNDEFINED} ]]; then
        # create subvolume on hard disk
        mount $destination 2>/dev/null
        if [[ -d $destination ]]; then
            display_alert "The hard disk already contains a '@var' subvolume." "$destination" "wrn"
            local oldext="old.`date +%Y-%m-%d_%H%M%S`"
            local rencmd="mv $destination $destination.$oldext"
            display_alert "Renaming existing @var subvolume" "$rencmd" ""
            $($rencmd)
        fi
        display_alert "Create new @var subolume on" "$destination" ""
        btrfs subvolume create $destination
        local rsynccmd="rsync -aHAXv $snapshotdir/$snapshotname/ $destination/"
        display_alert "Copy existing /var files to new destination:" "$destination" ""
        rsync -aHAXv $snapshotdir/$snapshotname/ $destination/

        # change /etc/fstab where /var is already a btrfs subvolume with the same name
        # we only need to change the device where the subvolume is located
        sed -i -E "s~^/dev/mapper/cryptroot\s+/var\s~/dev/mapper/${mapper_name} /var ~" /etc/fstab

    else
        display_alert "Relocation error. Please report an issue." "https://github.com/zhiverbox/armbian-userpatches/issues" "err"
        exit 1
    fi

    echo ""
    display_alert "Relocation of /var complete." "" "info"

    move_user_cache_dir

    # disable log2ram service
    disable_ramlog

    echo ""
    display_alert "We will reboot now to finish the hard disk setup!" "sudo reboot" "todo"
    echo ""
    press_any_key
    display_alert "REMINDER: First unlock cryptroot again after reboot!" "" ""
    echo -e \
"Whenever you reboot the zHIVErbox (deliberately or not), you'll have to unlock
the root partition (cryptroot) first. This is done by connecting to the boot
system (initramfs) via SSH on port 2222.
    ${ORANGE}ssh -p 2222 root@`get_local_ipv4_addr`${NC}
"
    press_any_key
    display_alert "Rebooting......................................................................." "" ""
    reboot
}

# if /var directory is moved to harddisk later let's move the user's personal
# cache directory '/home/user/.cache' (e.g. used by yarn) to /var/cache as well
move_user_cache_dir()
{
    display_alert "Move user's cache directory (/home/user/.cache) to:" "/var/cache/user" "info"
    if [[ -d /home/user/.cache ]]; then
        mv /home/user/.cache /var/cache/user 2>/dev/null
    else
        mkdir /var/cache/user
        chown user:user /var/cache/user
    fi
    sudo -u user ln -s /var/cache/user /home/user/.cache
}

disable_ramlog()
{
    echo ""
    display_alert "Disabling armbian-ramlog service..." "systemctl disable armbian-ramlog" ""
    echo -e \
"armbian-ramlog is useful to protect SD-Cards from too many frequent writes, but since
we moved /var/log to the hard disk, we can disable armbian-ramlog."
    echo ""
    systemctl disable armbian-ramlog
    systemctl disable armbian-zram-config
}

# main script
if $(check_part_is_luks $PART); then
    ask_mount_or_reformat
else
    do_format_disk
fi
