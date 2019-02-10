# What is zHIVErbox?
zHIVErbox - pronounced like 'cypher box' (sī′fər bŏks) - is an unfairly secure 
and unfairly cheap base system for the era of distributed networks (meshnets).  
Minds joining those networks form a HIVE (swarm) of self-sovereign individuals 
who DON'T TRUST, BUT VERIFY.    

zHIVErbox is based on Armbian, a Debian-based distribution for single-board ARM
development boards.  

# Why zHIVErbox?
Unfortunatly, security cannot be provided as a simple 'download'.  A secure 
system requires individual encryption and a secure source of randomness 
(entropy).  Therefore a secure system can only be created by self-sovereign 
individuals themself - and only for themself.  However, not everybody in a HIVE 
(society) can aquire the highly specialized knowledge and skills to create their 
own secure system from scratch.  

Therefore Cypherpunks write software and provide technology that can be used by 
other individuals to achieve the same level of security, privacy and self- 
sovereignty.  Those tools should be as user friendly as possible without 
compromising on security.  Ideally, those tools still provide a certain level of 
education, to retain their users from developing a 'blindly trusting attitude'.  
DON'T TRUST! VERIFY!  

zHIVErbox is a set of open source tools following these guidelines while
maintaining a `security first` approach.  

# zHIVERbox Features
While Armbian is perfect for development purposes, zHIVErbox customizations try 
to turn Armbian into a `Security Fortress` for production purposes.  The goal is
to reduce typical and possible attack vectors to a minimum.  

High-level differences with `Vanilla Armbian`:
* LUKS encrypted root partition with Btrfs filesystem / subvolumes (flat layout)
* LUKS encrypted data partition on the attached hard disk (Odroid HC1/HC2)
* Security-hardened Linux kernel
* Firewall (ferm) to block all inbound/outbound Clearnet traffic by default
* Enforces SSH public-key authentication
* Enforces all Internet traffic (incl. DNS) over Tor
* Tor-based time syncing instead of NTP (tordate and htpdate)
* Filter (proxy) for fine-graned access to Tor control port (onion grater)
* Ships with Cjdns (OSI-Layer-3 meshnet routing software) by default
* Ships with KadNode (DHT based, decentalized DNS alternative) by default
* Ships with IPFS (InterPlanetary File System) by default
* btrfs-snap tool for easy cron-based btrfs snapshots

For details please see the Security Design (SECURITY.md).

# Which hardware does zHIVErbox support?
As many meshnet applications (IPFS, Bitcoin, ...) require a significant amount
of storage, there's only one cheap and consumer-friendly single-board computer 
available right now - that allows to attach a hard disk in a solid/reliable way: 
The Odroid HC1/HC2
Therefore zHIVErbox is currently only designed for and tested on the 
`Odroid HC1/HC2` (and therefore implicitly their parent also, the `Odroid XU4`).  
But the zHIVErbox distribution would love to support more hardware in the future 
if it becomes available.  

# How to build a zHIVErbox image?
Please follow the build instructions (BUILD.md)

# How to install/flash a zHIVErbox image?
The build process only creates a `source image` which allows for distribution to
users, but needs to be customized and re-encrypted by every self-souvereign 
individual before installation on their own hardware.  zHIVErbox provides an 
`Installer` (currently an Ubuntu shell script) which helps the user with the 
required customizations.  Please see the installation instructions (INSTALL.md)
