#!/bin/bash
# shellcheck disable=SC2015

# Arch Linux Easy ZFS (ALEZ) installer 1.2
# by Dan MacDonald with contributions from John Ramsden

# Exit on error
set -o errexit -o errtrace

# Set a default locale during install to avoid mandb error when indexing man pages
export LANG=C

# This is required to fix grub's "failed to get canonical path" error
export ZPOOL_VDEV_NAME_PATH=1

version=1.2

# Colors
RED='\033[0;31m'
NC='\033[0m' # No Color

installdir="/mnt"
archzfs_pgp_key="F75D9D76"
zroot="zroot"

repo_directory="/usr/local/share/ALEZ"
repo_remote="danboid/ALEZ"

HEIGHT=0
WIDTH=0

show_path=false

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

check_latest() {
    # If repo doesn't exist, skip check
    [ -d "${repo_directory}" ] || return 0

    local tag remote_tag

    tag=$(
        cd "${repo_directory}" && \
        git describe --tags "$(git rev-list --tags --max-count=1)" || true
    )

    remote_tag="$(curl --silent \
        "https://api.github.com/repos/${repo_remote}/releases/latest" | \
        grep -Po '"tag_name": "\K.*?(?=")' || true
    )"

    # Dont fail, if check fails skip message
    if [ -n "${tag}" ] && [ -n "${tag}" ]; then
        [ "${remote_tag}" != "${tag}" ] && echo "${remote_tag}"
    fi

    return 0
}

check_internet() {
    ping -c 1 archlinux.org &> /dev/null || return 1
    return 0
}

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

bootloader_message() {
    if [[ "${bootloader}" =~ ^(g|G)$ ]]; then
        echo "mount -t zfs '${zroot}/boot/grub' '${installdir}/boot/grub'"
    else
        echo "mount '${efi_partition}' '${installdir}${esp_mountpoint}'"

        if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
            echo "mount --bind '${installdir}${esp_mountpoint}/env/zedenv-default' '${installdir}/boot'"
        fi
    fi
}

error_cleanup() {
    echo -e "${RED}WARNING:${NC} Error occurred. Unmounted datasets and exported ${zroot}"
}

# Run stuff in the ZFS chroot install function with optional message
chrun() {
    [[ -n "${2}" ]] && echo "${2}"
    arch-chroot "${installdir}" /bin/bash -c "${1}"
}

# List and enumerate attached disks function
lsdsks() {
    lsblk
    echo -e "\nAttached disks : \n"
    mapfile -t disks < <(lsblk | grep disk | awk '{print $1}')
    ndisks=${#disks[@]}
    for (( d=0; d<ndisks; d++ )); do
       echo -e "$d - ${disks[d]}\n"
    done
}

update_parts() {
    # shellcheck disable=SC2046
    mapfile -t partids < <(ls /dev/disk/by-id/* $(${show_path} && ls /dev/vd* || : ;))
    ptcount=${#partids[@]}
}

get_parts() {
    # Read partitions into an array and print enumerated
    update_parts
    for (( p=0; p<ptcount; p++ )); do
        echo "$p" "${partids[p]}"
    done
}

# Used for displaying partiions
lsparts() {
    echo -e "\nPartition layout:"
    lsblk

    echo -e "If you used alez to create your partitions, you likely want the one ending with -part2\n\n"
    echo -e "Available partitions:\n\n"

    # Read partitions into an array and print enumerated, only show path if show_path=true
    update_parts
    for (( p=0; p<ptcount; p++ )); do
        printf "%s%s\n" "${p} - ${partids[p]}" \
               "$([[ -L "${partids[p]}" ]] && printf "%s" "-> $(readlink "${partids[p]}")" || : ;)"
    done
}

zap_partition(){
    vgchange -an &> /dev/null
    mdadm --zero-superblock --force "${1}" &> /dev/null
    sgdisk --zap-all "${1}" &> /dev/null
}

bios_partitioning(){
    echo -e "GPT BIOS partitioning ${1}...\n"
    zap_partition "${1}"

    echo "Creating BIOS boot partition"
    sgdisk --new=1:0:+2M --typecode=1:EF02 "${1}"

    echo "Creating system partition"
    sgdisk --new=2:0:-"${free_space}"M --typecode=2:BF00 "${1}"

    echo "Set legacy BIOS boot flag"
    sgdisk -A 2:set:2 "${1}"
}

uefi_partitioning(){
    echo -e "GPT UEFI partitioning ${1}...\n"
    zap_partition "${1}"

    echo "Creating EFI partition"
    sgdisk --new=1:1M:+"${2}"M --typecode=1:EF00 "${1}"

    echo "Creating system partition"
    sgdisk --new=2:0:-"${free_space}"M --typecode=2:BF00 "${1}"

}

pkg_ver() {
    grep -oP "${1}" <(pacman -Ss '^'"${2}"'$' | grep -P "${2}"'\s')
}

depend_ver() {
    grep -oP '(?<=\b'"${1}\="')(.*)+(?=\b)' <(pacman -S --info "${2}" | grep "Depends On")
}

# Determine if zfs kernel is out of sync with linux .
# If needed download the correct kernel from the archive and install it.
get_matching_kernel() {
    echo "Getting matching kernel"
    local kern_suffix kern_match zfs_depend_ver kernel_version pkgdir ala
    kern_suffix=""
    [[ "${kernel_type}" =~ ^(l|L)$ ]] && kern_suffix="-lts"

    zfs_depend_ver="$(depend_ver "linux${kern_suffix}" "zfs-linux${kern_suffix}")"
    kernel_version="$(pkg_ver '(?<=\s)[[:digit:]].*?(?=($|\s))' "linux${kern_suffix}")"

    if [[ "${zfs_depend_ver}" != "${kernel_version}" ]]; then

        printf "%s\n%s\n" "zfs-linux${kern_suffix} package is out of sync with linux${kern_suffix}." \
            "Downloading kernel ${kernel_version} from archive"

        # Get package list
        ala="https://archive.archlinux.org/packages"
        kern_match="$(curl --silent "${ala}/.all/index.0.xz" | unxz | grep -P "linux${kern_suffix}-${zfs_depend_ver}")"

        echo "Found ${kern_match} in Arch Linux Archive"

        if [[ -z ${kern_match} ]]; then
            echo "Failed to find matching kernel"
            return 1
        fi

        pkg="${kern_match}.pkg.tar.xz";
        url="${ala}/l/linux${kern_suffix}/${pkg}"
        pkgdir="${installdir}"

        mkdir -p "${pkgdir}"
        {
            pushd "${pkgdir}" && wget "${url}"  && popd
        } &> /dev/null

        chrun "pacman -U --noconfirm /${pkg}" && rm "${pkgdir}/${pkg}"

    fi

    return 0
}

refresh_mirrors() {
    pacman -Sy --noconfirm &> /dev/null

    if hash reflector 2> /dev/null; then
    {
        echo "Refreshing mirrorlist"
        reflector --verbose --latest 25 \
                  --sort rate --save /etc/pacman.d/mirrorlist || :
    } 2> /dev/null | dialog --progressbox ${HEIGHT} ${WIDTH}
    fi
}

install_arch(){
    echo "Installing Arch base system..."
    {
        if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
            pacman -Sg base | cut -d ' ' -f 2 | sed 's/^linux$/linux-lts/g' | \
                    pacstrap "${installdir}" - linux-lts-headers
        else
            pacstrap "${installdir}" base linux-headers
        fi
    } 2> /dev/null

    chrun "if ! pacman-key -r F75D9D76; then
               pacman-key -r F75D9D76 --keyserver hkp://pool.sks-keyservers.net:80;
           fi && pacman-key --lsign-key F75D9D76" \
        "Adding Arch ZFS repo key in chroot..." 2> /dev/null

    echo "Add fstab entries..."
    fstab_output="$(genfstab -U "${installdir}")"
    (
        if [[ "${install_type}" =~ ^(u|U)$ ]] && ! [[ "${bootloader}" =~ ^(g|G) ]]; then
            echo "${fstab_output//\/mnt\/mnt/\/mnt}"
        else
            echo "${fstab_output}"
        fi
    ) > "${installdir}/etc/fstab"

    echo "Add Arch ZFS pacman repo..."
    echo -e "\n[archzfs]\nServer = https://archzfs.com/\$repo/x86_64" >> "${installdir}/etc/pacman.conf"

    echo -e "Export ZPOOL_VDEV_NAME_PATH\n"
    echo -e "\nexport ZPOOL_VDEV_NAME_PATH=1" >> "${installdir}/etc/profile"

    echo "Modify HOOKS in mkinitcpio.conf..."
    sed -i 's/HOOKS=.*/HOOKS="base udev autodetect modconf block keyboard zfs filesystems"/g' \
           "${installdir}/etc/mkinitcpio.conf"

    get_matching_kernel

    {
        if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
            chrun "pacman -Sy; pacman -S --noconfirm zfs-linux-lts" "Installing ZFS LTS in chroot..."
        else
            chrun "pacman -Sy; pacman -S --noconfirm zfs-linux" "Installing ZFS in chroot..."
        fi
    } 2> /dev/null

    echo -e "Enable systemd ZFS service...\n"
    chrun "systemctl enable zfs.target"
}

add_grub_entry(){
    chrun "grub-mkconfig -o /boot/grub/grub.cfg" "Create GRUB configuration"
    echo "Adding Arch ZFS entry to GRUB menu..."
    local kern_suffix
    kern_suffix=""
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
        kern_suffix="-lts"
    fi
    # shellcheck disable=SC1004
    awk -i inplace '/10_linux/ && !x {print $0; print "\
menuentry \"Arch Linux ZFS\" {\n\
    \tlinux /ROOT/default/@/boot/vmlinuz-linux'"${kern_suffix}"' '"zfs=${zroot}/ROOT/default"' rw\n\
    \tinitrd /ROOT/default/@/boot/initramfs-linux'"${kern_suffix}"'.img\n\
}"; x=1; next} 1' "${installdir}/boot/grub/grub.cfg"
}

install_grub(){
    chrun "grub-install /dev/${disks[${1}]}" "Installing GRUB to /dev/${disks[${1}]}..." 2> /dev/null
}

install_grub_efi(){
    {
        chrun "pacman -S --noconfirm grub efibootmgr os-prober" \
            "Installing GRUB for UEFI in chroot..."
        add_grub_entry

        # Install GRUB EFI
        chrun "grub-install --target=x86_64-efi --efi-directory=${1} --bootloader-id=GRUB" \
            "Installing grub-efi to ${1}"
    } 2> /dev/null
}

gen_sdboot_entry(){
    cat <<- EOF > "${installdir}/${1}/loader/entries/zedenv-default.conf"
        title           [default] (Arch Linux)
        linux           /env/zedenv-default/vmlinuz-${2}
        initrd          /env/zedenv-default/initramfs-${2}.img
        options         zfs=${zroot}/ROOT/default rw
EOF
}

install_sdboot(){
    chrun "bootctl --path=${1} install" "Installing systemd-boot to ${1}" 2> /dev/null
    mkdir -p "${installdir}/${1}/loader/entries"
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
        gen_sdboot_entry "${1}" "linux-lts"
    else
        gen_sdboot_entry "${1}" "linux"
    fi

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

# Input:
# Output:
#  - variable 'disks' - array containing all the disks found
get_disks(){
    mapfile -t disks < <(lsblk | grep disk | awk '{print $1}')
    ndisks=${#disks[@]}
    for (( d=0; d<ndisks; d++ )); do
       echo "$d"; echo "${disks[d]}"
    done
}

# Input:
#  - $1 - aray name containing the choices
#  - $2 - title
#  - $3 - menu description
# Output
#  - stdout - selected item or nothing if Cancel was pressed
dialog_menu() {
    local -a PARAMS
    local COUNT=0
    local -n ARRAY=$1
    local VALUE

    for VALUE in "${ARRAY[@]}"; do
        ((COUNT++)) || true # 0++ returns 1 which trips our ERR trap
        PARAMS+=( "${COUNT}" "${VALUE}" )
    done

    COUNT=$(
        dialog --stdout --clear --title "$2" \
            --menu "$3" $HEIGHT $WIDTH $COUNT "${PARAMS[@]}" \
            || true # Protect the dialog from ERR trap when user selects "Cancel"
    )

    if [ -n "$COUNT" ]; then
        # Array is numbered from 0
        echo "${ARRAY[$COUNT-1]}"
    fi
}

# Define a multiline variable
define() {
    # shellcheck disable=SC2086
    IFS=$'\n' read -r -d '' ${1} || : ;
}

fetch_archzfs_key() {
    declare -a keyservers=(
        'hkp://pool.sks-keyservers.net:80'
        # 'hkp://pgp.mit.edu:80'                    # Replace with working keyservers
        # 'hkp://ipv4.pool.sks-keyservers.net:80'
    )

    {
    # Try default keyserver first
    if pacman-key -r "${archzfs_pgp_key}"; then
        pacman-key --lsign-key "${archzfs_pgp_key}" && return 0
    fi
    for ks in "${keyservers[@]}"; do
        if pacman-key -r "${archzfs_pgp_key}" --keyserver "${ks}"; then
            pacman-key --lsign-key "${archzfs_pgp_key}" && return 0
        fi
    done
    } &> /dev/null
    return 1
}

## MAIN ##

trap error_cleanup ERR     # Run on error
trap unmount_cleanup EXIT  # Run on exit

# Check script is being run as root
if [[ $EUID -ne 0 ]]; then
   echo "The Arch Linux Easy ZFS installer must be run as root"
   exit 1
fi

if [ -f /sys/firmware/efi/fw_platform_size ]; then
    install_type=u
    system_mode=UEFI
else
    install_type=b
    system_mode=BIOS
fi

connected=1
check_internet && connected=0

remote_tag="$(check_latest)"

define welcome_msg <<EOF
Running in ${system_mode} mode.$(
    [ "${connected}" -eq 1 ] && printf "\n%s\n%s" \
        "You are not connected to the internet." \
        "Please connect to the Internet before running ALEZ."
)
EOF

# shellcheck disable=SC2154
dialog --title "The Arch Linux Easy ZFS (ALEZ) installer v${version}" \
       --msgbox "${welcome_msg}" ${HEIGHT} ${WIDTH}

if [ -n "${remote_tag}" ]; then
    define release_msg <<EOF
A newer release of ALEZ is available.
${remote_tag}
EOF

    # shellcheck disable=SC2154
    dialog --title "New release available" --msgbox "${release_msg}" ${HEIGHT} ${WIDTH}
fi

[ "${connected}" -eq 1 ] && exit 1

kernel_type=$(dialog --stdout --clear --title "Kernel type" \
                     --menu "Please select:" $HEIGHT $WIDTH 4 "s" "Stable (standard)" "l" "Longterm")

if [[ "${install_type}" =~ ^(u|U)$ ]]; then
    bootloader=$(dialog --stdout --clear --title "UEFI bootloader" \
                        --menu "Please select:" $HEIGHT $WIDTH 4 "s" "systemd-boot" "g" "GRUB on ZFS")

    if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
        esp_mountpoint="/mnt/efi"
    else
        esp_mountpoint="/boot/efi"
    fi

else
    bootloader="g"
fi

# Check if any VirtIO devices exist
if lsblk | grep -E 'vd.*disk'; then
    [ -d /dev/disk/by-path/ ] && show_path=true
fi

# No frills GPT partitioning
autopart="Do you want to select a drive to be auto-partitioned?"
declare -a aflags=(--clear --title 'Partitioning' --yesno)
while dialog "${aflags[@]}" "${autopart}" $HEIGHT $WIDTH; do

    if dialog --clear --title "Disk layout" --yesno "View disk layout before choosing zpool partitions?" $HEIGHT $WIDTH; then
        file="$(mktemp)"
        lsdsks > "${file}"
        dialog --tailbox "${file}" 0 0
    fi

    get_disks
    blkdev=$( dialog_menu disks "Install type" "Select a disk" )
    if [ -z "$blkdev" ]; then
        # Cancel pressed, let's restart the main loop
        continue
    fi
    blkdev="/dev/$blkdev"
    free_space=$(dialog --stdout --clear --title "Should I leave free space after ZFS partition?" --inputbox "Enter unused space in MB" $HEIGHT $WIDTH "0")

    msg="ALL data on $blkdev will be lost? Proceed?"
    if dialog --clear --title "Partition disk?" --yesno "${msg}" $HEIGHT $WIDTH; then
        msg="Shred partitions before partitioning $blkdev (slow)?"
        if dialog --clear --title "Shred disk?" --defaultno --yesno "${msg}" $HEIGHT $WIDTH; then
            dialog --prgbox "shred --verbose -n1 $blkdev" 10 70
        fi

        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            bios_partitioning "$blkdev" | dialog --programbox 10 70
        else
            esp_size=512
            if [[ "${bootloader}" =~ ^(s|S) ]]; then
                msg="Enter the size of the esp (512 or greater in MiB),\n1024 or greater recommended to hold multiple kernels"
                esp_size=$(dialog --stdout --clear --title "UEFI partition size" --inputbox "${msg}" $HEIGHT $WIDTH "2048")
                while [ "$esp_size" -lt "512" ]; do
                    esp_size=$(dialog --stdout --clear --title "UEFI partition size" --inputbox "${msg}" $HEIGHT $WIDTH "2048")
                done
            fi
            uefi_partitioning "$blkdev" "${esp_size}" | dialog --programbox 10 70
        fi
    fi
    autopart="Do you want to select another drive to be auto-partitioned?"
    declare -a aflags=(--clear --title 'Partitioning' --defaultno --yesno)
done

# Create zpool
msg="Do you want to create a new zpool?"
while dialog --clear --title "New zpool?" --yesno "${msg}" $HEIGHT $WIDTH; do
    zpconf=$(dialog --stdout --clear --title "Install type" \
                    --menu "Single disc, or mirrored zpool?" $HEIGHT $WIDTH 4 "s" "Single disc" "m" "Mirrored")

    if dialog --clear --title "Disk layout" --yesno "View partition layout?" $HEIGHT $WIDTH; then
        partsfile="$(mktemp)"
        lsparts > "${partsfile}"
        # shellcheck disable=SC2086
        dialog --tailbox ${partsfile} 0 0
    fi

    partinfo="$(get_parts)"

    if [ "$zpconf" == "s" ]; then
        msg="Select a partition.\n\nIf you used alez to create your partitions,\nyou likely want the one ending with -part2"
        # shellcheck disable=SC2086
        zps=$(dialog --stdout --clear --title "Choose partition" \
                     --menu "${msg}" $HEIGHT $WIDTH "$(( 2 + ptcount))" ${partinfo})
        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            # shellcheck disable=SC2046
            zpool create -f -d -m none -o ashift=12 $(print_features) "${zroot}" "${partids[$zps]}"
        else
            zpool create -f -d -m none -o ashift=12 "${zroot}" "${partids[$zps]}"
        fi
        dialog --title "Success" --msgbox "Created a single disk zpool with ${partids[$zps]}...." ${HEIGHT} ${WIDTH}
        break
    elif [ "$zpconf" == "m" ]; then
        # shellcheck disable=SC2086
        zp1=$(dialog --stdout --clear --title "First zpool partition" \
                     --menu "Select the number of the first partition" $HEIGHT $WIDTH "$(( 2 + ptcount ))" ${partinfo})
        # shellcheck disable=SC2086
        zp2=$(dialog --stdout --clear --title "Second zpool partition" \
                     --menu "Select the number of the second partition" $HEIGHT $WIDTH "$(( 2 + ptcount ))" ${partinfo})

        echo "Creating a mirrored zpool..."
        if [[ "${install_type}" =~ ^(b|B)$ ]]; then
            # shellcheck disable=SC2046
            zpool create "${zroot}" mirror -f -d -m none \
                -o ashift=12 \
                $(print_features) "${partids[$zp1]}" "${partids[$zp2]}"
        else
            zpool create "${zroot}" mirror -f -d -m none -o ashift=12 "${partids[$zp1]}" "${partids[$zp2]}"
        fi
        dialog --title "Success" --msgbox "Created a mirrored zpool with ${partids[$zp1]} ${partids[$zp2]}...." ${HEIGHT} ${WIDTH}
        break
    fi
done

{
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
    zfs set acltype=posixacl "${zroot}"
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
} | dialog --progressbox 10 70

if [[ "${install_type}" =~ ^(u|U)$ ]]; then

    if dialog --clear --title "Disk layout" --yesno "View partition layout before creating esp?" $HEIGHT $WIDTH; then
        partsfile="$(mktemp)"
        lsparts > "${partsfile}"
        # shellcheck disable=SC2086
        dialog --tailbox ${partsfile} 0 0
    fi

    partinfo="$(get_parts)"

    msg="Enter the number of the partition above that you want to use for an esp.\n\n"
    msg+="If you used alez to create your partitions,\nyou likely want the one ending with -part1"
    # This shellcheck exception is necessary to keep the partinfo variable unquoted.
    # Adding quotes around ${partinfo} here breaks the esp dialog command.
    # shellcheck disable=SC2086
    esp=$(dialog --stdout --clear --title "Install type" \
                 --menu "$msg" \
                 $HEIGHT $WIDTH "$(( 2 + ptcount))" ${partinfo})

    efi_partition="${partids[$esp]}"
    mkfs.fat -F 32 "${efi_partition}"| dialog --progressbox 10 70

    mkdir -p "${installdir}${esp_mountpoint}" "${installdir}/boot"
    mount "${efi_partition}" "${installdir}${esp_mountpoint}"

    if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
        mkdir -p "${installdir}${esp_mountpoint}/env/zedenv-default"
        mount --bind "${installdir}${esp_mountpoint}/env/zedenv-default" "${installdir}/boot"
    fi
fi

dialog --title "Begin install?" --msgbox "Setup complete, begin install?" ${HEIGHT} ${WIDTH}

refresh_mirrors

if ! fetch_archzfs_key; then
    dialog --title "Installation error" \
        --msgbox "ERROR: Failed to fetch archzfs key" ${HEIGHT} ${WIDTH}
    exit 1
fi

install_arch | dialog --progressbox 30 70

# Install GRUB BIOS
if [[ "${install_type}" =~ ^(b|B)$ ]]; then

    chrun "pacman -S --noconfirm grub os-prober" "Installing GRUB in chroot..." 2> /dev/null | dialog --progressbox 30 70

    add_grub_entry

    autopart="Do you want to install GRUB onto any of the attached disks?"
    declare -a aflags=(--clear --title 'Install GRUB' --yesno)
    while dialog "${aflags[@]}" "${autopart}" $HEIGHT $WIDTH; do

        msg="NOTE: If you have installed Arch onto a mirrored pool then you should install GRUB onto both disks\n"
        dialog --title "Install GRUB" --msgbox "${msg}" ${HEIGHT} ${WIDTH}

        if dialog --clear --title "Disk layout" --yesno "View partition layout before GRUB install?" $HEIGHT $WIDTH; then
            partsfile="$(mktemp)"
            lsparts > "${partsfile}"
            # shellcheck disable=SC2086
            dialog --tailbox ${partsfile} 0 0
        fi

        partinfo="$(get_disks)"
        update_parts

        # shellcheck disable=SC2086
        grubdisk=$(dialog --stdout --clear --title "Install type" \
                 --menu "Enter the number of the partition on which you want to install GRUB:" \
                 ${HEIGHT} ${WIDTH} "${ptcount}" ${partinfo})

        install_grub "${grubdisk}" | dialog --progressbox 30 70

        autopart="Do you want to select another drive to install GRUB onto?"
        declare -a aflags=(--clear --title 'Install GRUB' --defaultno --yesno)
    done
else
    {
        if [[ "${bootloader}" =~ ^(s|S)$ ]]; then
            install_sdboot "${esp_mountpoint}"
        else
            install_grub_efi "${esp_mountpoint}"
        fi
    } 2> /dev/null | dialog --progressbox 30 70
fi

{
    echo "Update initial ramdisk (initrd) with ZFS support..."
    if [[ "${kernel_type}" =~ ^(l|L)$ ]]; then
        chrun "mkinitcpio -p linux-lts"
    else
        chrun "mkinitcpio -p linux"
    fi
} 2> /dev/null | dialog --progressbox 30 70

unmount_cleanup

clear

# shellcheck disable=SC2091
cat <<EOT
# Installation complete. You may now reboot into your new install.

# If you want to mount the newly installed system and install more
# packages you can do so via:

# Mount datasets and partitions
zpool import -R '${installdir}' '${zroot}'
$(bootloader_message)

# Enter chroot
arch-chroot '${installdir}'

  # inside chroot
  pacman -S ....
  exit

# back out of chroot
umount -R '${installdir}'
zfs umount -a && zpool export '${zroot}'
EOT
