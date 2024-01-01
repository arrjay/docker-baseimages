#!/bin/bash
set -ex

export DEBIAN_FRONTEND=noninteractive

platform="yum"
type yum || platform=""
type dnf && platform="dnf"
type zypper && platform="zypper"
[ -f /debootstrap/debootstrap ] && platform="apt"

echo "detected platform ${platform}" 1>&2

case "${platform}" in
  yum|dnf)
    # bring RPM back online from export so it works in chroot. bdb only...
    # do we...have dump files?
    dbpath=$(rpm --eval '%_dbpath')
    dfiles=("${dbpath}"/*.dump)
    [[ -e "${dfiles}" ]] && {
      echo "rebuilding rpm db" 1>&2

      cd "${dbpath}"

      for x in *.dump ; do
        dest="$(basename "${x}" .dump)"
        /usr/lib/rpm/rpmdb_load "${dest}" < "${x}"
        rm "${x}"
      done

      cd -

      rpm --rebuilddb || { rebuilddbdirs=( /usr/share/rpmrebuilddb.* ) && [ -d "${rebuilddbdirs[0]}" ]
        mv "${rebuilddbdirs[0]}"/* /usr/share/rpm
        rmdir "${rebuilddbdirs[0]}"
      }
    }

    echo "cleaning all yum repos" 1>&2
    "${platform}" clean all

    [ -d /etc/yum.repos.d/stage2 ] && {
      stage2_yum=( /etc/yum.repos.d/stage2/*.repo )
      [ -e "${stage2_yum[0]}" ] && {
        echo "adding additional yum repos" 1>&2
        for r in "${stage2_yum[@]}" ; do
          mv "${r}" /etc/yum.repos.d
        done
      }
      rm -rf "/etc/yum.repos.d/stage2"
    }
  ;;
  zypper)
    echo "importing gpg keys" 1>&2
    for k in /etc/pki/rpm-gpg/RPM-GPG-KEY-* ; do
      rpmkeys --import "${k}"
    done
    echo "verifying package installations" 1>&2
    "${platform}" -n verify
  ;;
  apt)
    echo "running second stage bootstrap" 1>&2
    dpkg-divert --rename /usr/bin/ischroot && ln -s /bin/true /usr/bin/ischroot
    dpkg-divert --rename /usr/sbin/invoke-rc.d && ln -s /bin/true /usr/sbin/invoke-rc.d
    echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections
    debootstrap_args="--second-stage --merged-usr"
    read -r suite < debootstrap/suite
    case "${suite}" in
      xenial|precise|trusty) debootstrap_args="--second-stage" ;;
      # work around dash preinst wanting to manipulate the sh.distrib (and friends) man page
      bionic) mkdir -p /usr/share/man/man1 ;;
    esac
    /debootstrap/debootstrap ${debootstrap_args} || { cat /debootstrap/debootstrap.log ; exit 1; }
    rm -f /var/log/debootstrap.log

    case "${suite}" in
      # undo the dash hack
      bionic)
        rm /usr/share/man/man1/sh.1.gz
        rmdir /usr/share/man/man1 /usr/share/man
      ;;
    esac

    echo "installing sources.list" 1>&2
    install -m644 /apt-sources.list /etc/apt/sources.list && rm /apt-sources.list

    echo "updating apt against newly installed sources.list" 1>&2
    apt-get update || { ls -lR / ; exit 1 ; }

    echo "configuring localepurge, installing localepurge" 1>&2
    printf '%s\n' 'localepurge localepurge/use-dpkg-feature boolean false' \
                  'localepurge localepurge/mandelete boolean true' \
                  'localepurge localepurge/dontbothernew boolean true' \
                  'localepurge localepurge/showfreedspace boolean false' \
                  'localepurge localepurge/quickndirtycale boolean true' \
                  'localepurge localepurge/verbose boolean false' \
                  'localepurge localepurge/nopurge string en,en_US,en_US.UTF-8' | debconf-set-selections
    apt-get install localepurge
    printf '%s\n' 'localepurge localepurge/use-dpkg-feature boolean true' | debconf-set-selections
    dpkg-reconfigure localepurge

    echo "installing apt-transport-https, debsums, ca-certificates libfile-find-rule-perl" 1>&2
    apt-get install apt-transport-https debsums ca-certificates libfile-find-rule-perl

    echo "initializing debsums" 1>&2
    debsums_init || /usr/lib/untrustedhost/scripts/debsums_init

    echo "configuring ssl library apt behaviour"
    libssl="$(dpkg -l | awk '$2 ~ /libssl[^-]/ {print $2}')"
    printf '%s\n' "${libssl} libraries/restart-without-asking boolean true" | debconf-set-selections

    echo "perferming dist-upgrade against new sources.list"
    apt-get dist-upgrade
  ;;
esac

# if we find a systemd lib, migrate /var/run to /run
found_systemd=0
systemd_lib=( /lib/x86_64-linux-gnu/libsystemd.so* /lib64/libsystemd.so* /lib/libsystemd.so* )
for f in "${systemd_lib[@]}" ; do [ -f "${f}" ] && found_systemd=1 ; done
[ "${found_systemd}" == 1 ] && {
  [ -L /var/run ] || {
    mkdir -p /run
    for f in /var/run/* ; do
      [ -e "${i}" ] && mv -f "${i}" /run
    done
    rm -rf /var/run
    ln -sf /run /var/run
  }
}

# if we find ourselves, delete ourselves.
# shellcheck disable=SC2128
{
  if [[ -s "$BASH_SOURCE" ]] && [[ -x "$BASH_SOURCE" ]]; then
          rm "$(readlink -f "$BASH_SOURCE")"
  fi
}
