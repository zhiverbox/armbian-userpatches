# zHIVErbox build instructions
The build process only creates a `source image` which allows for distribution
to users, but needs to be customized and re-encrypted by every self-souvereign
individual before installation on their own hardware.

## Make sure you have `tor` and `torsocks` installed and running on the build
system
```
sudo apt-get install tor torsocks
sudo systemctl status tor@default.service
```
While this is not a requirement for a vanilla Armbian build, zhiverbox build needs
this as it onionfies the apt sources of the target system. This happens within
the `customize-image.sh` which runs in a chroot environment where no system
serices like `tor` can be installed or started. So `tor.service` needs to be
running on the build system already before the build process is started.

## Checkout the zHIVErbox fork of Armbian
```
mkdir zhiverbox
cd zhiverbox
torsocks git clone https://github.com/zhiverbox/armbian-build --branch zhiverbox
cd armbian-build
rm -rf userpatches
torsocks git clone https://github.com/zhiverbox/armbian-userpatches userpatches
```

## Build zHIVErbox source image
```
cd zhiverbox/armbian-build
./compile.sh zhiverbox
```

When the build process is finished, the resulting source image will be in
`zhiverbox/armbian-build/output/images/` having the file extension `.img.src`.
This source image can be customized into a **flashable** image using the
`zHIVErbox-Installer` (see INSTALL.md).

## Obsolete: Provide a pre-built (armhf) version of Cjdns
For some reason the Armbian build process sometimes hangs, if Cjdns is build
inside the Qemu environment. If that happens a workaround is to provide a
pre-built version of Cjdns and put it in
`userpatches/overlay/build/precompiled/cjdns-v20.1-armhf`. To enable it,
edit the file `userpatches/overlay/build/helpers.sh` at the function
`install_cjdns()`, comment the line `install_cjdns_service /opt/src/cjdns`
and uncomment the line
`install_cjdns_service /tmp/overlay/build/precompiled/cjdns-v20.1-armhf`
instead.

**How to get a pre-build Cjdns?**
Either cross-compile Cjdns for 32-bit ARM (armhf) or install a vanilla
Armbian on the Odroid HC1/HC2 first and build Cjdns according to the build
instructions: https://github.com/cjdelisle/cjdns/blob/master/README.md

When done, copy the whole cjdns directory via rsync/ssh to your workstation at
`zhiverbox/armbian-build/userpatches/overlay/opt/src/cjdns`
