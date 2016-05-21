Arch Linux Easy ZFS (ALEZ) installer 0.1
========================================

**by Dan MacDonald**



WHAT IS ALEZ?
-------------

ALEZ (pronounced like 'ales', as in beer) is a shell script to simplify the process of installing Arch Linux using the ZFS file system.

ALEZ automates the processes of partitioning disks, creating and configuring a zpool and some basic datasets, installing a base Arch Linux system and configuring and installing the GRUB bootloader so that they all play nicely with ZFS. The datasets are structured so as to be usable for boot environments.


LIMITATIONS
-----------

This is the very first release of this script. It has a few limitations you need to be aware of:

* 64 bit, x86 (amd64) Arch is the only platform supported by the Arch ZFS repo and hence this script.

* No UEFI or automated dual-booting support.

* This script currently only supports partitioning or installing to drives using GPT which requires a small (1-2 MB) unformatted BIOS bootloader partition. This is created automatically by the partitioning feature of ALEZ. I have not been able to get GRUB to install to an MBR, ZFS formatted drive without using the symbolic link hack mentioned on the Arch wiki so I'm currently a bit uncomfortable about using Arch ZFS with MBR hence why MBR isn't supported by this script currently.

* ALEZ currently only supports creating single or double-drive (mirrored) zpools - no RAIDZ support yet.


HOW DO I USE IT?
----------------

The official Arch installation images don't support ZFS. I plan to upload an Arch installation image complete with the ZFS packages and this script pre-installed soon but until then you either have to manually add the Arch ZFS repo and install the ZFS package when booting off the Arch install image BEFORE running the script OR you can create your own custom Arch install CD that includes the required ZFS packages. You must install either zfs-linux, zfs-linux-lts or zfs-linux-git (but only one of those) before you can run this script. ALEZ installs zfs-linux into the new system by default.

See [this link for instructions on creating a custom Arch installer with ZFS support](https://wiki.archlinux.org/index.php/ZFS#Embed_the_archzfs_packages_into_an_archiso)

Otherwise, add [this repo to your /etc/pacman.conf](https://wiki.archlinux.org/index.php/Unofficial_user_repositories#archzfs)

Apart from having one of those three ZFS packages installed, ALEZ must be run as root plus you need a working internet connection so that it can download the required packages. Once you have booted an Arch install disc, you have a suitable ZFS package installed and you have copied the script onto your system simply run alez.sh from any location and answer the few simple questions it prompts you for.
