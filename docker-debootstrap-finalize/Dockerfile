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
RUN bash -c '. /etc/os-release && sed -i -e "s/CODENAME/${VERSION_CODENAME}/g" /etc/apt/sources.list'

# reference: https://wiki.ubuntu.com/ReducingDiskFootprint

# configure apt to never install recommended packages
# and drop unneeded package components (i18n, docs)
COPY apt.conf.d/* /etc/apt/apt.conf.d/
RUN chmod 0644 /etc/apt/apt.conf.d/*

# configure dpkg to not install docs
COPY dpkg/dpkg.cfg.d/* /etc/dpkg/dpkg.cfg.d/
RUN chmod 0644 /etc/dpkg/dpkg.cfg.d/*

# update package indexes _now_
RUN apt-get update

# usrmerge depends on libfile-find-rule-perl (for bionic at least) - install now
RUN apt-get install libfile-find-rule-perl

# remove in-docker noodlyness
RUN rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot && \
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d
