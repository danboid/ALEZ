Arch Linux Easy ZFS (ALEZ) installer
====================================

**by Dan MacDonald and John Ramsden**



WHAT IS ALEZ?
-------------

ALEZ (pronounced like 'ales', as in beer) is a shell script to simplify the process of installing Arch Linux using the ZFS file system.

ALEZ automates the processes of partitioning disks, creating and configuring a ZFS pool and some basic datasets, installing a base Arch Linux system and configuring and installing the GRUB bootloader so that they all play nicely with ZFS. The datasets are structured so as to be usable for ([zedenv](https://github.com/johnramsden/zedenv)) boot environments.


LIMITATIONS
-----------

ALEZ has a few limitations you need to be aware of:

* 64 bit, x86 (amd64) Arch is the only platform supported by the Arch ZFS repo and hence this script.

* No automated multiboot support.

* This script currently only supports partitioning or installing to drives using GPT which requires a small (1-2 MB) unformatted BIOS bootloader partition. This is created automatically by the partitioning feature of ALEZ. ALEZ does not support creating MBR partitions. 

* ALEZ currently only supports creating single or double-drive (mirrored) pools - there is no RAIDZ support yet.


HOW DO I USE IT?
----------------

The easiest way to use ALEZ is to [download archlinux-alez.](https://github.com/danboid/ALEZ/releases), which is a version of Arch Linux remastered to include ZFS support and the Arch Linux Easy ZFS (ALEZ) installer. [Transfer the iso onto a USB drive](https://wiki.archlinux.org/index.php/USB_flash_installation_media) (or burn it to a disc) just as you would for the regular Arch iso, boot it and then type 'alez' at the prompt to start the installer.



Stable vs LTS kernel
--------------------

The stable kernel is the default Linux kernel installed as part of a regular base Arch install. The stable kernel is normally more current than the LTS kernel so it may offer more hardware support and/or features but it also gets updated more often than the LTS kernel. As a result, if you choose the stable kernel option you may encounter the error:

```
The following package cannot be upgraded due to unresolvable dependecies: zfs-linux
```

When this happens you have two easy options. Either wait 24 hours for the Arch ZFS repo to update its packages to be in sync with the new Arch stable kernel package or install the LTS kernel.



TROUBLESHOOTING
---------------


archzfs key import fails
------------------------

If ALEZ abruptly 'completes' near the start of the install, it could be that it failed to import the key for the archzfs repo because the archlinux-keyring PGP signatures package included on the iso is outdated. Rather than waiting for a new ISO to be uploaded you can follow the instructions in create-alez-iso.txt to create an updated ISO.


Installing under virt-manager 1.x / qemu
----------------------------------------

GRUB fails to install under VMs created using the virt-manager 1.x defaults. If you wish to run ALEZ under virt-manager 1.x or qemu, modify the VMs CPU settings to enable 'Copy host CPU configuration' mode.
