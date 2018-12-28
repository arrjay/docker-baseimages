FROM build/pre

# shut up, apt
ENV DEBIAN_FRONTEND=noninteractive

# work around maintainer scripts not realizing you're _in docker_ ;)
RUN dpkg-divert --rename /usr/bin/ischroot && ln -s /bin/true /usr/bin/ischroot && \
    dpkg-divert --rename /usr/sbin/invoke-rc.d && ln -s /bin/true /usr/sbin/invoke-rc.d && \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections

# finish debootstrap here
RUN /debootstrap/debootstrap --second-stage --merged-usr || { cat /debootstrap/debootstrap.log ; exit 1; }

# clean up debootstrap
RUN rm /var/log/bootstrap.log

# init sources.list for all repos now. we just had the base before.
COPY apt/sources.list /etc/apt/sources.list
RUN chmod 0644 /etc/apt/sources.list

# reference: https://wiki.ubuntu.com/ReducingDiskFootprint

# configure apt to never install recommended packages
# and drop unneeded package components (i18n, docs)
COPY apt.conf.d/* /etc/apt/apt.conf.d/
RUN chmod 0644 /etc/apt/apt.conf.d/*

# configure dpkg to not install docs
COPY dpkg/dpkg.cfg.d/* /etc/dpkg/dpkg.cfg.d/
RUN chmod 0644 /etc/dpkg/dpkg.cfg.d/*

# update package indexes _now_
RUN apt-get -q update

# preconfigure localepurge, install, run, reconfigure to use deb
RUN printf '%s\n' "localepurge localepurge/use-dpkg-feature boolean false" \
                  "localepurge localepurge/mandelete boolean true" \
                  "localepurge localepurge/dontbothernew boolean true" \
                  "localepurge localepurge/showfreedspace boolean false" \
                  "localepurge localepurge/quickndirtycale boolean true" \
                  "localepurge localepurge/verbose boolean false" \
                  "localepurge localepurge/nopurge string en,en_US,en_US.UTF-8" \
     | debconf-set-selections && \
    apt-get install -qy localepurge && \
    localepurge && \
    echo "localepurge localepurge/use-dpkg-deature boolean true" | debconf-set-selections && \
    dpkg-reconfigure localepurge

# eat the existing docs and i18n
RUN { find /usr/share/doc -depth -type f ! -name copyright|xargs rm || true ; } ; \
    { find /usr/share/doc -empty|xargs rmdir || true ; } ; \
    rm -rf /usr/share/man /usr/share/groff /usr/share/info /usr/share/lintian /usr/share/linda /var/cache/man ; \
    find /usr/share/locale /usr/share/i18n/locales -mindepth 1 -maxdepth 1 ! -name 'en' ! -name 'en_US' -print0 | xargs -0 rm -r

# configure debsums separate
RUN apt-get install -qy debsums && \
    debsums_init

# install additional packages now, try a dist upgrade
RUN apt-get install -qy apt-transport-https ca-certificates xz-utils && \
    apt-get -qy dist-upgrade

RUN apt-get clean all && \
    rm -rf /var/lib/apt/lists/*

RUN rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot && \
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d

