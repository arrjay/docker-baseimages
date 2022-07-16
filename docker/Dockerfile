# handoff from build.sh script so far
FROM build/usrmerge

# shut up, apt
ENV DEBIAN_FRONTEND=noninteractive

# force a sane path in here
ENV PATH=/usr/bin:/bin:/usr/sbin:/sbin

# work around maintainer scripts not realizing you're _in docker_ ;)
RUN dpkg-divert --rename /usr/bin/ischroot && ln -s /bin/true /usr/bin/ischroot && \
    dpkg-divert --rename /usr/sbin/invoke-rc.d && ln -s /bin/true /usr/sbin/invoke-rc.d && \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections

# preconfigure localepurge, install, run, reconfigure to use deb
RUN libssl=$(dpkg -l | grep libssl | awk '{print $2}') \
 && printf '%s\n' "localepurge localepurge/use-dpkg-feature boolean false" \
                  "localepurge localepurge/mandelete boolean true" \
                  "localepurge localepurge/dontbothernew boolean true" \
                  "localepurge localepurge/showfreedspace boolean false" \
                  "localepurge localepurge/quickndirtycale boolean true" \
                  "localepurge localepurge/verbose boolean false" \
                  "localepurge localepurge/nopurge string en,en_US,en_US.UTF-8" \
                  "${libssl} libraries/restart-without-asking boolean true" \
     | debconf-set-selections && \
    apt-get install localepurge && \
    localepurge && \
    echo "localepurge localepurge/use-dpkg-feature boolean true" | debconf-set-selections && \
    dpkg-reconfigure localepurge

# eat the existing docs and i18n
RUN { find /usr/share/doc -depth -type f ! -name copyright|xargs rm || true ; } ; \
    { find /usr/share/doc -empty|xargs rmdir || true ; } ; \
    rm -rf /usr/share/man /usr/share/groff /usr/share/info /usr/share/lintian /usr/share/linda /var/cache/man ; \
    find /usr/share/locale /usr/share/i18n/locales -mindepth 1 -maxdepth 1 ! -name 'en' ! -name 'en_US' -print0 | xargs -0 rm -r

# scripts for us and downstreams
RUN mkdir -p /usr/lib/untrustedhost
ADD scripts /usr/lib/untrustedhost/scripts

# configure debsums separate
RUN apt-get install debsums && \
    /usr/lib/untrustedhost/scripts/debsums_init

# install additional packages now, try a dist upgrade
RUN apt-get install apt-transport-https ca-certificates xz-utils gnupg && \
    apt-get dist-upgrade

# finally, clean up anything apt left about
RUN apt-get clean all && \
    rm -rf /var/lib/apt/lists/*

# and of course, undo any in-docker hackery
RUN rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot && \
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d

# replace /opt with symlink to /var/opt
RUN rmdir /opt && ln -sf ./var/opt /opt

# preconfigure facter...
RUN mkdir -p /etc/puppetlabs
ADD facter /etc/puppetlabs/facter

# and add build stamps
ADD facts.d /usr/lib/untrustedhost/facts.d
RUN chmod 0644 /usr/lib/untrustedhost/facts.d/*
