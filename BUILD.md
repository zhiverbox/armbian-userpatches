# zHIVErbox build instructions
The build process only creates a `source image` which allows for distribution to
users, but needs to be customized and re-encrypted by every self-souvereign 
individual before installation on their own hardware.

## Checkout the zHIVErbox fork of Armbian
```
mkdir zhiverbox
cd zhiverbox
torsocks git clone https://github.com/zhiverbox/armbian-build --branch zhiverbox
cd armbian-build
rm -rf userpatches
torsocks git clone https://github.com/zhiverbox/armbian-userpatches userpatches
```

## Provide a pre-built (armhf) version of Cjdns
For some reason the Armbian build process hangs, if Cjdns is build inside the 
Qemu environment. The current workaround is to provide a pre-built version of 
Cjdns and put it in `userpatches/overlay/opt/src/cjdns`.

How? Either cross-compile Cjdns for 32-bit ARM (armhf) or install a vanilla 
Armbian on the Odroid HC1/HC2 first and build Cjdns according to the build 
instructions: https://github.com/cjdelisle/cjdns/blob/master/README.md

When done, copy the whole cjdns directory via rsync/ssh to your workstation at
`zhiverbox/armbian-build/userpatches/overlay/opt/src/cjdns`

## Build zHIVErbox source image
```
cd zhiverbox/armbian-build
./compile.sh zhiverbox
```

When the build process is finished, the resulting source image will be in 
`zhiverbox/armbian-build/output/images/` having the file extension `.img.src`.
This source image can be customized into a **flashable** image using the 
`zHIVErbox-Installer` (see INSTALL.md). 
