FROM archlinux/base

RUN pacman -Syu --noconfirm --needed \
                base base-devel git archiso && \
    pacman-key --init && \
    pacman-key -r F75D9D76 && pacman-key --lsign-key F75D9D76

RUN mkdir -p /opt/alez && \
    cp -r /usr/share/archiso/configs/releng /opt/alez/iso

# RUN printf 'git\nzfs-linux\n' > /opt/alez/iso/packages.x86_64
# Add archzfs before [core]
RUN sed -i '/^\[core\]/i [archzfs]\nServer = http://archzfs.com/$repo/x86_64\n'  \
    /opt/alez/iso/pacman.conf

RUN mkdir -p /opt/alez/iso/out /opt/alez/iso/airootfs/usr/local/bin

COPY alez-downloader.sh /opt/alez/iso/airootfs/usr/local/bin/alez
COPY motd /opt/alez/iso/usr/local/bin/airootfs/etc/

RUN chmod +x /opt/alez/iso/airootfs/usr/local/bin/alez

VOLUME /opt/alez/iso/out

WORKDIR /opt/alez/iso
CMD ["./build.sh", "-v"]
