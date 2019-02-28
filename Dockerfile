FROM archlinux/base

ARG ALEZ_BUILD_DIR='/opt/alez'
ARG ALEZ_PUBLISHER='alez'
ARG ALEZ_ISO='archlinux-alez'
ARG ARCHZFS_KEY='F75D9D76'

RUN pacman -Syu --noconfirm --needed base base-devel git archiso

RUN rm -rf /etc/pacman.d/gnupg && \
    pacman-key --init && pacman-key --populate archlinux && \
    pacman-key -r "${ARCHZFS_KEY}" && pacman-key --lsign-key "${ARCHZFS_KEY}"

RUN mkdir -p "${ALEZ_BUILD_DIR}" && \
    cp -r /usr/share/archiso/configs/releng "${ALEZ_BUILD_DIR}/iso" && \
    mkdir -p "${ALEZ_BUILD_DIR}/iso/out" "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin"

# Add archzfs before [core]
RUN sed -i '/^\[core\]/i [archzfs]\n\
            SigLevel = Optional TrustAll\n\
            Server = http://archzfs.com/$repo/x86_64\n' \
    "${ALEZ_BUILD_DIR}/iso/pacman.conf"

RUN printf 'git\narchzfs-linux\n' >> "${ALEZ_BUILD_DIR}/iso/packages.x86_64"

COPY alez-downloader.sh "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin/alez"
COPY motd "${ALEZ_BUILD_DIR}/iso/airootfs/etc/"

RUN chmod +x "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin/alez"

VOLUME "${ALEZ_BUILD_DIR}/iso/out"

WORKDIR "${ALEZ_BUILD_DIR}/iso"
CMD ["bash", "-c", "./build.sh -v -N \"${ALEZ_ISO}\" -P \"${ALEZ_PUBLISHER}\""]
