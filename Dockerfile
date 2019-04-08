FROM archlinux/base

ARG ALEZ_BUILD_DIR='/opt/alez'
ARG ARCHZFS_KEY='F75D9D76'

RUN pacman -Syu --noconfirm --needed base base-devel git archiso reflector curl

RUN mkdir ~/.gnupg && echo "disable-ipv6" >> ~/.gnupg/dirmngr.conf
RUN pacman-key --init && pacman-key --populate archlinux && \
    pacman-key -r "${ARCHZFS_KEY}" --keyserver hkp://pool.sks-keyservers.net:80 && pacman-key --lsign-key "${ARCHZFS_KEY}"

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

RUN printf 'git\narchzfs-linux\nreflector\n' >> "${ALEZ_BUILD_DIR}/iso/packages.x86_64"

COPY alez-downloader.sh "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin/alez"
COPY motd "${ALEZ_BUILD_DIR}/iso/airootfs/etc/"

RUN git clone --branch master --single-branch --depth 1 \
    https://github.com/danboid/ALEZ.git \
    ${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/share/ALEZ 

RUN chmod +x "${ALEZ_BUILD_DIR}/iso/airootfs/usr/local/bin/alez"

VOLUME "${ALEZ_BUILD_DIR}/iso/out"

WORKDIR "${ALEZ_BUILD_DIR}/iso"
CMD ["./build.sh", "-v"]
