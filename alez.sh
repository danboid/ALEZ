#!/bin/bash

# Arch Linux Easy ZFS (ALEZ) installer 0.66
# by Dan MacDonald 2016-2018 with contributions from John Ramsden

# Exit on error
set -o errexit -o errtrace

# Set a default locale during install to avoid mandb error when indexing man pages
export LANG=C

version=0.66

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

installdir="/mnt"
archzfs_pgp_key="F75D9D76"
zroot="zroot"

declare -a zpool_bios_features
zpool_bios_features=(
    'feature@lz4_compress=enabled'
    'feature@multi_vdev_crash_dump=disabled'
    'feature@large_dnode=disabled'
    'feature@sha512=disabled'
    'feature@skein=disabled'
    'feature@edonr=disabled'
    'feature@userobj_accounting=disabled'
)

print_features() {
    # Prefix each property with '-o '
    echo "${zpool_bios_features[@]/#/-o }"
}

unmount_cleanup() {
    {
        umount -R "${installdir}" || : ;
        zfs umount -a && zpool export "${zroot}" || : ;
    } &> /dev/null
}

error_cleanup() {
    echo -e "${RED}WARNING:${NC} Error occurred. Unmounted datasets and exported ${zpool}"
    # Other cleanup
}

# Run stuff in the ZFS chroot install function with optional message
chrun() {
    [[ ! -z "${2}" ]] && echo "${2}"
	arch-chroot "${installdir}" /bin/bash -c "$1"
}

# List and enumerate attached disks function
lsdsks() {
	lsblk
	echo -e "\nAttached disks : \n"
	disks=(`lsblk | grep disk | awk '{print $1}'`)
	ndisks=${#disks[@]}
	for (( d=0; d<${ndisks}; d++ )); do
	   echo -e "$d - ${disks[d]}\n"
	done
}

lsparts() {
    echo -e "\nPartition layout:"
    lsblk

    echo -e "If you used this script to create your partitions, choose partitions ending with -part\n\n"
    echo -e "Available partitions:\n\n"

    # Read partitions into an array and print enumerated
    partids=(
        $(ls /dev/disk/by-id/* $([ -d /dev/disk/by-partuuid/ ] && ls /dev/disk/by-partuuid/* || : ;))
    )
    ptcount=${#partids[@]}

    for (( p=0; p<${ptcount}; p++ )); do
        echo -e "$p - ${partids[p]} -> $(readlink ${partids[p]})\n"
    done
}

bios_partitioning(){
    echo "GPT BIOS partitioning ${1}..."
    mdadm --zero-superblock --force "${1}" &> /dev/null

    parted --script "${1}" \
        mklabel gpt \
        mkpart non-fs 0% 2 \
        mkpart primary 2 100% set 1 bios_grub on set 2 boot on
}

uefi_partitioning(){
    echo "GPT UEFI partitioning ${1}..."

    esp_size=512
    if [[ "${bootloader}" =~ ^(s|S) ]]; then
        read -p "Enter the size of the esp (in MiB), 1024 or greater reccomended to hold multiple kernels : " esp_size
        while [ "$esp_size" -lt "512" ]; do
            read -p "Enter the size of the esp (in MiB), 1024 or greater reccomended to hold multiple kernels : " esp_size
        done
    fi

    mdadm --zero-superblock --force "${1}" &> /dev/null
    sgdisk --zap-all "${1}"
    sgdisk --new="1:1M:+${esp_size}M" --typecode=1:EF00 "${1}"
    sgdisk --new=2:0:0 --typecode=2:BF01 "${1}"

}

install_arch(){
    echo "Installing Arch base system..."
    pacstrap ${installdir} base
    
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
		chrun "pacman -Sy; pacman -S --noconfirm linux-lts" "Installing LTS kernel..."
	fi

    echo "Add fstab entries..."
    fstab_output="$(genfstab -U "${installdir}")"
    (
        if [[ "${install_type}" =~ ^(u|U)$ ]] && ! [[ "${bootloader}" =~ ^(g|G) ]]; then
            echo "${fstab_output}" | sed "s:/mnt/mnt:/mnt:g"
        else
            echo "${fstab_output}"
        fi
    ) > "${installdir}/etc/fstab"

    echo "Add Arch ZFS pacman repo..."
    echo -e "\n[archzfs]\nServer = http://archzfs.com/\$repo/x86_64" >> "${installdir}/etc/pacman.conf"

    echo "Modify HOOKS in mkinitcpio.conf..."
    sed -i 's/HOOKS=.*/HOOKS="base udev autodetect modconf block keyboard zfs filesystems"/g' "${installdir}/etc/mkinitcpio.conf"

    chrun "pacman-key -r F75D9D76; pacman-key --lsign-key F75D9D76" "Adding Arch ZFS repo key in chroot..."
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
		chrun "pacman -Sy; pacman -S --noconfirm zfs-linux-lts" "Installing ZFS LTS in chroot..."
	else
		chrun "pacman -Sy; pacman -S --noconfirm zfs-linux" "Installing ZFS stable in chroot..."
	fi

    echo -e "Enable systemd ZFS service...\n"
    chrun "systemctl enable zfs.target"
}

add_grub_entry(){
	echo "Adding Arch ZFS entry to GRUB menu..."
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
    awk -i inplace '/10_linux/ && !x {print $0; print "menuentry \"Arch Linux ZFS\" {\n\tlinux /ROOT/default/@/boot/vmlinuz-linux-lts \
        '"zfs=${zroot}/ROOT/default"' rw\n\tinitrd /ROOT/default/@/boot/initramfs-linux-lts.img\n}"; x=1; next} 1' "${installdir}/boot/grub/grub.cfg"
    else
    awk -i inplace '/10_linux/ && !x {print $0; print "menuentry \"Arch Linux ZFS\" {\n\tlinux /ROOT/default/@/boot/vmlinuz-linux \
        '"zfs=${zroot}/ROOT/default"' rw\n\tinitrd /ROOT/default/@/boot/initramfs-linux.img\n}"; x=1; next} 1' "${installdir}/boot/grub/grub.cfg"
	fi
}
	

install_grub(){
    chrun "pacman -S --noconfirm grub os-prober" "Installing GRUB in chroot..."

	add_grub_entry
    
    # Write script to create symbolic links for partition ids to work around a GRUB bug that can cause grub-install to fail - hackety hack
    echo -e "ptids=(\`cd /dev/disk/by-id/;ls\`)\nidcount=\${#ptids[@]}\nfor (( c=0; c<\${idcount}; c++ )) do\ndevs[c]=\$(readlink /dev/disk/by-id/\${ptids[\$c]} | sed 's/\.\.\/\.\.\///')\nln -s /dev/\${devs[c]} /dev/\${ptids[c]}\ndone" > ${installdir}/home/partlink.sh
    echo -e "ptids=(\`cd /dev/disk/by-partuuid/;ls\`)\nidcount=\${#ptids[@]}\nfor (( c=0; c<\${idcount}; c++ )) do\ndevs[c]=\$(readlink /dev/disk/by-partuuid/\${ptids[\$c]} | sed 's/\.\.\/\.\.\///')\nln -s /dev/\${devs[c]} /dev/\${ptids[c]}\ndone" >> ${installdir}/home/partlink.sh

    echo -e "Create symbolic links for partition ids to work around a grub-install bug...\n"
    chrun "sh /home/partlink.sh > /dev/null 2>&1"
    rm -f ${installdir}/home/partlink.sh

    lsdsks

    # Install GRUB
    echo -e "NOTE: If you have installed Arch onto a mirrored pool then you should install GRUB onto both disks\n"
    read -p "Do you want to install GRUB onto any of the attached disks? (N/y): " dogrub
    while [ "$dogrub" == "y" ] || [ "$dogrub" == "Y" ]; do
        read -p "Enter the number of the disk to install GRUB to : " gn
        if [ "$gn" -ge 0 -a "$gn" -le "$ndisks" ]; then
                chrun "grub-install /dev/${disks[$gn]}" "Installing GRUB to /dev/${disks[$gn]}..."
        else
                echo "Please enter a number between 0 and $(($ndisks-1))"
        fi
        read -p "Do you want to install GRUB to another disk? (N/y) : " dogrub
    done
}

install_grub_efi(){
    chrun "pacman -S --noconfirm grub efibootmgr os-prober" "Installing GRUB for UEFI in chroot..."
    
    add_grub_entry

    # Write script to create symbolic links for partition ids to work around a GRUB bug that can cause grub-install to fail - hackety hack
    echo -e "ptids=(\`cd /dev/disk/by-id/;ls\`)\nidcount=\${#ptids[@]}\nfor (( c=0; c<\${idcount}; c++ )) do\ndevs[c]=\$(readlink /dev/disk/by-id/\${ptids[\$c]} | sed 's/\.\.\/\.\.\///')\nln -s /dev/\${devs[c]} /dev/\${ptids[c]}\ndone" > ${installdir}/home/partlink.sh
    echo -e "ptids=(\`cd /dev/disk/by-partuuid/;ls\`)\nidcount=\${#ptids[@]}\nfor (( c=0; c<\${idcount}; c++ )) do\ndevs[c]=\$(readlink /dev/disk/by-partuuid/\${ptids[\$c]} | sed 's/\.\.\/\.\.\///')\nln -s /dev/\${devs[c]} /dev/\${ptids[c]}\ndone" >> ${installdir}/home/partlink.sh

    echo -e "Create symbolic links for partition ids to work around a grub-install bug...\n"
    chrun "sh /home/partlink.sh > /dev/null 2>&1"
    rm -f ${installdir}/home/partlink.sh

    # Install GRUB
    chrun "grub-install --target=x86_64-efi --efi-directory=${1} --bootloader-id=GRUB" "Installing grub-efi to ${1}"
}

install_sdboot(){
    chrun "bootctl --path=${1} install" "Installing systemd-boot to ${1}"
    mkdir -p "${installdir}/${1}/loader/entries"
    cat <<- EOF > "${installdir}/${1}/loader/entries/zedenv-default.conf"
        title           [default] (Arch Linux)
        linux           /env/zedenv-default/vmlinuz-linux
        initrd          /env/zedenv-default/initramfs-linux.img
        options         zfs=${zroot}/ROOT/default rw
EOF
    cat <<- EOF > "${installdir}/${1}/loader/loader.conf"
       timeout 3
       default zedenv-default
EOF
}

check_mountdir(){
    if [ "$(ls -A ${installdir})" ]; then
    echo "Install directory ${installdir} isn't empty"
    tempdir="$(mktemp -d)"
    if [ -d "${tempdir}" ]; then
        echo "Using temp directory ${tempdir}"
        installdir="${tempdir}"
    else
        echo "Exiting, error occurred"
        exit 1
    fi
fi
}

## MAIN ##

trap error_cleanup ERR     # Run on error
trap unmount_cleanup EXIT  # Run on exit

# Check script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "The Arch Linux Easy ZFS installer must be run as root"
   exit 1
fi

echo -e "\nThe Arch Linux Easy ZFS (ALEZ) installer v${version}\n\n"
echo -e "Please make sure you are connected to the Internet before running ALEZ.\n\n"

read -p "Install type UEFI [u] or non-UEFI/BIOS [b]? (u/b): " install_type
while ! [[ "${install_type}" =~ ^(u|U|b|B)$ ]]; do
    read -p "Install type UEFI [u] or non-UEFI/BIOS [b]? (u/b): " install_type
done

read -p "Kernel type Stable [s] or Longterm [l]? (s/l): " kernel_type
while ! [[ "${kernel_type}" =~ ^(s|S|l|L)$ ]]; do
    read -p "Kernel type Stable [s] or Longterm [l]? (s/l): " kernel_type
done

if [[ "${install_type}" =~ ^(u|U)$ ]]; then
    read -p "UEFI bootloader systemd-boot [s] or GRUB on ZFS [g]? (s/g): " bootloader
    while ! [[ "${bootloader}" =~ ^(s|S|g|G)$ ]]; do
        read -p "UEFI bootloader systemd-boot [s] or GRUB on ZFS [g]? (s/g): " bootloader
    done

    if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
        esp_mountpoint="/mnt/efi"
    else
        esp_mountpoint="/boot/efi"
    fi

else
    bootloader="g"
fi

# No frills GPT partitioning
read -p "Do you want to select a drive to be auto-partitioned? (N/y): " dopart
while [[ "$dopart" =~ ^(y|Y)$ ]]; do
    lsdsks
    blkdev=-1
    while [ "$blkdev" -ge "$ndisks" ] || [ "$blkdev" -lt 0 ]; do
        read -p "Enter the number of the disk you want to partition, between 0 and $(($ndisks-1)) : " blkdev
    done

    read -p "ALL data on /dev/${disks[$blkdev]} will be lost? Proceed? (N/y) : " blkconf
    if [[ "${blkconf}" =~ ^(y|Y)$ ]]; then

        read -p "Shred partitions before partitioning /dev/${disks[$blkdev]} (slow)? (N/y) : " shreddisk
        if [[ "${shreddisk}" =~ ^(y|Y)$ ]]; then
            shred --verbose -n1 "/dev/${disks[$blkdev]}"
        fi

        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            bios_partitioning "/dev/${disks[$blkdev]}"
        else
            uefi_partitioning "/dev/${disks[$blkdev]}"
        fi
    else
        break
    fi
    read -p "Do you want to partition another device? (N/y) : " dopart
done

# Create zpool
zpconf="0"
while read -p "Do you want to create a single or double disk (mirrored) zpool? (1/2) : " zpconf ; do 
    lsparts
    if [ "$zpconf" == "1" ]; then 
        read -p "Enter the number of the partition above that you want to create a new zpool on : " zps
        echo "Creating a single disk zpool..."
        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            zpool create -f -d -m none -o ashift=12 $(print_features) "${zroot}" "${partids[$zps]}"
        else
            zpool create -f -d -m none -o ashift=12 "${zroot}" "${partids[$zps]}"
        fi
        break
    elif [ "$zpconf" == "2" ]; then
        read -p "Enter the number of the first partition : " zp1
        read -p "Enter the number of the second partition : " zp2
        echo "Creating a mirrored zpool..."
        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            zpool create "${zroot}" mirror -f -d -m none \
                -o ashift=12 \
                $(print_features) "${partids[$zp1]}" "${partids[$zp2]}"
        else
            zpool create "${zroot}" mirror -f -d -m none -o ashift=12 "${partids[$zp1]}" "${partids[$zp2]}"
        fi
        break
    fi
    echo "Please enter 1 or 2"
done 

echo "Creating datasets..."
zfs create -o mountpoint=none "${zroot}"/ROOT
zfs create -o mountpoint=none "${zroot}"/data
zfs create -o mountpoint=legacy "${zroot}"/data/home

{ zfs create -o mountpoint=/ "${zroot}"/ROOT/default || : ; }  &> /dev/null

# GRUB only datasets
if [[ "${bootloader}" =~ ^(g|G)$ ]]; then
    zfs create -o canmount=off "${zroot}"/boot
    zfs create -o mountpoint=legacy "${zroot}"/boot/grub
fi

# This umount is not always required but can prevent problems with the next command
zfs umount -a

echo "Setting ZFS properties..."
zfs set atime=off "${zroot}"
zfs set compression=on "${zroot}"
zpool set bootfs="${zroot}"/ROOT/default "${zroot}"

check_mountdir

echo "Exporting and importing pool..."
zpool export "${zroot}"
zpool import "$(zpool import | grep id: | awk '{print $2}')" -R "${installdir}" "${zroot}"

mkdir -p "${installdir}/home"
mount -t zfs "${zroot}/data/home" "${installdir}/home"

if [[ "${bootloader}" =~ ^(g|G)$ ]]; then
    mkdir -p "${installdir}/boot/grub"
    mount -t zfs "${zroot}/boot/grub" "${installdir}/boot/grub"
fi

if [[ "${install_type}" =~ ^(u|U)$ ]]; then
    lsparts
    read -p "Enter the number of the partition above that you want to use for an esp : " esp
    efi_partition="${partids[$esp]}"
    mkfs.fat -F 32 "${efi_partition}"

    mkdir -p "${installdir}${esp_mountpoint}" "${installdir}/boot"
    mount "${efi_partition}" "${installdir}${esp_mountpoint}"

    if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
        mkdir -p "${installdir}${esp_mountpoint}/env/zedenv-default"
        mount --bind "${installdir}${esp_mountpoint}/env/zedenv-default" "${installdir}/boot"
    fi
fi

{ pacman-key -r "${archzfs_pgp_key}" && pacman-key --lsign-key "${archzfs_pgp_key}" ; } &> /dev/null

install_arch

if [[ "${install_type}" =~ ^(b|B)$ ]]; then
    install_grub
else
    if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
        install_sdboot "${esp_mountpoint}"
    else
        install_grub_efi "${esp_mountpoint}"
    fi
fi

echo "Update initial ramdisk (initrd) with ZFS support..."
if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
	chrun "mkinitcpio -p linux-lts"
else
	chrun "mkinitcpio -p linux"
fi

unmount_cleanup
echo "Installation complete. You may now reboot into your Arch ZFS install."
