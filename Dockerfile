FROM archlinux/base

ARG ALEZ_BUILD_DIR='/opt/alez'
ARG ARCHZFS_KEY='F75D9D76'

RUN pacman -Syu --noconfirm --needed base base-devel git archiso reflector curl wget

RUN mkdir ~/.gnupg && echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf
RUN pacman-key --init && pacman-key --populate archlinux && \
    if ! pacman-key -r "${ARCHZFS_KEY}"; then pacman-key -r "${ARCHZFS_KEY}" --keyserver hkp://pool.sks-keyservers.net:80; fi && pacman-key --lsign-key "${ARCHZFS_KEY}"

RUN mkdir -p "${ALEZ_BUILD_DIR}" && \
    cp -r /usr/share/archiso/configs/releng "${ALEZ_BUILD_DIR}/iso" && \
    sed --in-place '/wpa_actiond/d' "${ALEZ_BUILD_DIR}/iso/packages.x86_64" && \
    mkdir -p \
        "${ALEZ_BUILD_DIR}/iso/out" \
        "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin" \
        "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/share"

# Add archzfs before [core]
RUN sed -i '/^\[core\]/i [archzfs]\n\
            SigLevel = Optional TrustAll\n\
            Server = http://archzfs.com/$repo/x86_64\n' \
    "${ALEZ_BUILD_DIR}/iso/pacman.conf"

RUN printf 'git\narchzfs-linux\nreflector\nwget\nlinux\nlinux-firmware\ndhcpcd\nless\nmdadm' >> \
           "${ALEZ_BUILD_DIR}/iso/packages.x86_64"

RUN printf '\nsystemctl enable dhcpcd' >> \
           "${ALEZ_BUILD_DIR}/iso/airootfs/root/customize_airootfs.sh"

## In case of kernel mismatch ##

RUN mkdir -p "${ALEZ_BUILD_DIR}/iso/airootfs/root/customrepo/x86_64" && \
    cd "${ALEZ_BUILD_DIR}/iso/airootfs/root/customrepo/x86_64" && \
    wget "https://archive.archlinux.org/packages/l/linux/linux-5.4.15.arch1-1-x86_64.pkg.tar.zst" && \
    repo-add "${ALEZ_BUILD_DIR}/iso/airootfs/root/customrepo/x86_64/customrepo.db.tar.gz" "${ALEZ_BUILD_DIR}/iso/airootfs/root/customrepo/x86_64/linux-5.4.15.arch1-1-x86_64.pkg.tar.zst"

RUN sed -i '/^\[core\]/i [customrepo]\n\
            SigLevel = Optional TrustAll\n\
            Server = file:///opt/alez/iso/airootfs/root/customrepo/$arch\n' \
    "${ALEZ_BUILD_DIR}/iso/pacman.conf"

RUN pacman -Syy

## ##

COPY motd "${ALEZ_BUILD_DIR}/iso/airootfs/etc/"

# Copy in current directory to allow git tag checking
COPY . "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/share/ALEZ"

RUN chmod +x "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/share/ALEZ/alez.sh"

RUN ln -s "/usr/local/share/ALEZ/alez.sh" "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin/alez"

VOLUME "${ALEZ_BUILD_DIR}/iso/out"

WORKDIR "${ALEZ_BUILD_DIR}/iso"
CMD ["./build.sh", "-v"]
