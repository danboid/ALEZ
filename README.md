Arch Linux Easy ZFS (ALEZ) installer
====================================

**by Dan MacDonald and John Ramsden**



WHAT IS ALEZ?
-------------

ALEZ (pronounced like 'ales', as in beer) is a shell script to simplify the process of installing Arch Linux using the ZFS file system.

ALEZ automates the processes of partitioning disks, creating and configuring a ZFS pool and some basic datasets, installing a base Arch Linux system 
and configuring and installing the GRUB or systemd bootloader so that they all play nicely with ZFS. 

The default datasets are configured ready to be managed with the ([zedenv](https://github.com/johnramsden/zedenv)) boot environment manager.


LIMITATIONS
-----------

ALEZ has a few limitations you need to be aware of:

* x86-64/amd64 is the only platform supported by the Arch ZFS repo and hence this script.

* ALEZ only supports partitioning or installing to drives using GPT. ALEZ does not support creating MBR partitions but both BIOS and UEFI machines are supported.

* It only supports creating single or double disk (mirrored) pools - there is no RAIDZ support.


HOW DO I USE IT?
----------------

The easiest way to use ALEZ is to [download archlinux-alez.](https://github.com/danboid/ALEZ/releases), which is a version of Arch Linux remastered to include ZFS support and the Arch Linux Easy ZFS (ALEZ) installer. 
[Transfer the iso onto a USB drive](https://wiki.archlinux.org/index.php/USB_flash_installation_media) (or burn it to a disc) just as you would for the regular Arch iso, boot it and then type 'alez' at the prompt to start the installer.



Stable vs LTS kernel
--------------------

The stable kernel is the default Linux kernel installed as part of a regular base Arch install. The stable kernel is normally more current than the LTS kernel so it may offer more hardware support and/or features. It gets updated more often than the LTS kernel.



TROUBLESHOOTING
---------------


archzfs key import fails
------------------------

If ALEZ abruptly 'completes' near the start of the install, it could be that it failed to import the key for the archzfs repo because the archlinux-keyring PGP signatures package included on the iso is outdated. Rather than waiting for a new ISO to be uploaded you can follow the instructions in create-alez-iso.txt to create an updated ISO.


Running ALEZ under virt-manager / qemu
----------------------------------------

GRUB fails to install under VMs created using the virt-manager defaults because it defaults to using an IDE disk bus. Change your VM disk bus to VirtIO or SATA before running ALEZ.



You may also want to check out my other ZFS-related repos, [Creating ZFS disks under Linux](https://github.com/danboid/creating-ZFS-disks-under-Linux) and [ZFS aliases](https://github.com/danboid/ZFS-aliases) - my most used ZFS commands as aliases.
