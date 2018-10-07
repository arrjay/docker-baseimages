#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

platform="yum"
type yum || platform=""
type dnf && platform="dnf"
type zypper && platform="zypper"
[ -f /debootstrap/debootstrap ] && platform="apt"

echo "detected platform ${platform}" 1>&2

case "${platform}" in
  yum|dnf)
    echo "rebuilding rpm db" 1>&2
    # bring RPM back online from export so it works in chroot.
    dbpath=$(rpm --eval '%_dbpath')
    cd "${dbpath}"

    for x in *.dump ; do
      dest="$(basename "${x}" .dump)"
      /usr/lib/rpm/rpmdb_load "${dest}" < "${x}"
      rm "${x}"
    done

    cd -

    rpm --rebuilddb || { rebuilddbdirs=( /var/lib/rpmrebuilddb.* ) && [ -d "${rebuilddbdirs[0]}" ]
      mv "${rebuilddbdirs[0]}"/* /var/lib/rpm
      rmdir "${rebuilddbdirs[0]}"
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
    esac
    /debootstrap/debootstrap ${debootstrap_args} || { cat /debootstrap/debootstrap.log ; exit 1; }

    echo "installing sources.list" 1>&2
    install -m644 /apt-sources.list /etc/apt/sources.list && rm /apt-sources.list

    echo "installing apt-transport-https, debsums, ca-certificates" 1>&2
    apt-get update
    apt-get --no-install-recommends install -qy apt-transport-https debsums ca-certificates
    apt-get -qy dist-upgrade
    debsums_init

    echo "cleaning all apt activity" 1>&2
    apt-get clean all
    rm -rf /var/lib/apt/lists/*
    rm /usr/bin/ischroot && dpkg-divert --rename --remove /usr/bin/ischroot
    rm /usr/sbin/invoke-rc.d && dpkg-divert --rename --remove /usr/sbin/invoke-rc.d
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
