FROM build/pre

RUN dpkg-divert --rename /usr/bin/ischroot && ln -s /bin/true /usr/bin/ischroot && \
    dpkg-divert --rename /usr/sbin/invoke-rc.d && ln -s /bin/true /usr/sbin/invoke-rc.d && \
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections

RUN /debootstrap/debootstrap --second-stage --merged-usr || { cat /debootstrap/debootstrap.log ; exit 1; }

COPY sources.list /etc/apt/sources.list

RUN chmod 0644 /etc/apt/sources.list

RUN apt-get -q update && \
    apt-get --no-install-recommends install -qy apt-transport-https debsums ca-certificates xz-utils && \
    apt-get -qy dist-upgrade && \
    debsums_init

RUN apt-get clean all && \
    rm -rf /var/lib/apt/lists/*

RUN rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot && \
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d

