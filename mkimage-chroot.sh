#!/usr/bin/env bash

set -eu
set -o pipefail

# locate source files
source="${BASH_SOURCE[0]}"
while [ -h "${source}" ]; do
  srcdir="$( cd -P "$( dirname "${source}" )" && pwd )"
  source="$(readlink "${source}")"
  [[ ${source} != /* ]] && source="${srcdir}/${source}"
done
srcdir="$( cd -P "$( dirname "${source}" )" && pwd )"

devtgz="${srcdir}/devs.tar.gz"

debootstrap_dir="${srcdir}/debootstrap"

[ "${UBUNTU_URI:=}" ] || UBUNTU_URI=https://mirrors.kernel.org/ubuntu/
echo "using ${UBUNTU_URI} as debootstrap mirror."

# reset umask
umask 0022

# check for device file archive
if [ ! -f "${devtgz}" ] ; then
  printf 'missing the /dev tar archive (run sudo mkdev.sh)\n' 1>&2
  exit 2
fi

# get checkout directory git revision information
coderev="$(git rev-parse --short HEAD)"
  # uncommitted
{ git diff-index --quiet --cached HEAD -- &&
  # extra
  git diff-files --quiet ; } || coderev="${coderev}-DIRTY"

case "${coderev}" in
  *-DIRTY) echo "WARNING: git tree is dirty, sleeping 5 seconds for running confirmation. build will not use cache."
           sleep 5
           FORCE_BUILD=1
           ;;
esac

timestamp="$(date +%s)"

echo "building ${coderev} at ${timestamp}"

# create a scratch directory to use for working files
wkdir=$(env TMPDIR=/var/tmp mktemp -d)
export TMPDIR="${wkdir}"

__cleanup () {
  echo "working directory was ${wkdir}" 1>&2
  [ -z "${NOCLEAN:-}" ] && { echo "removing workdir" 1>&2 ; sudo rm -rf "${wkdir}" ; }
}

trap __cleanup EXIT ERR

sudo () { env "$@"; }
# if we're not root, bring sudo to $sudo
{
  [ "$(id -u)" != "0" ] && {
    echo "you are not root, wrapping commands in sudo..." 1>&2
    sudo () { command sudo env "$@"; }
  } ;
} || echo "your are already root, 'sudo' is env in this script."

create_chroot_tarball () {
  local packagemanager distribution release subdir __debootstrap debootstrap_file __centos_contentdir
  local repos_d repos2_d gpg
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"
  local gpg_keydir
  # check that we have a gpg dir for dist.
  gpg_keydir="${subdir}/gpg-keys"
  # shellcheck disable=SC2015
  [ ! -d "${gpg_keydir}" ] && { echo "missing ${gpg_keydir}" 1>&2 ; exit 1 ; } || true
  debootstrap_file="${debootstrap_dir}/scripts/${release}"

  # if we didn't get packagemanager, distribution display usage
  # shellcheck disable=SC2015
  case "${packagemanager}" in
    *yum) packagemanager=yum ; arch=x86_64 ;;
    *dnf) packagemanager=dnf ; arch=x86_64 ;;
    *zyp) packagemanager=zyp ; arch=x86_64 ;;
    *apt) packagemanager=apt ; arch=amd64 ; [ ! -e "${debootstrap_file}" ] && { echo "missing ${debootstrap_file}" 1>&2 ; exit 1 ; } || true ;;
    *) echo "unknown packagemanager" 1>&2 ; exit 240 ;;
  esac

  # reread arch at this point, in case we are building for...not x86_64/amd64.
  [ -f "${subdir}/arch" ] && read -r arch < "${subdir}/arch"

  # mock out commands via function overload here - which is exactly what we want, but drives shellcheck batty.
  # shellcheck disable=SC2032,SC2033
  {
    type rpm 2> /dev/null 1>&2 && {
      # any RPM calls here should be in our chroot.
      rpm() { sudo rpm --root "${rootdir}" "${@}"; }
    }
    debootstrap() {
       # run using our included function set
       # with a minimal install
       # for our architecture
       # with flags as called
       # in our chroot
       # using the UBUNTU_URI mirror.
       sudo DEBOOTSTRAP_DIR="${srcdir}/debootstrap" \
         bash "${debootstrap_dir}/debootstrap" \
           --verbose \
           --variant=minbase \
           "--arch=${arch}" \
           "${@}" \
           "${rootdir}" \
          "${UBUNTU_URI}"
    }
    type dnf 2> /dev/null 1>&2 && {
      echo "using dnf for yum calls" 1>&2
      yum() {
        # call with flags to disable weak dependencies
        # manually set release version
        # into the chroot
        # using a config we made
        # with flags as called
        sudo dnf \
          --setopt=install_weak_deps=False --best \
          --releasever="${release}" \
          --installroot="${rootdir}" \
          -c "${yumconf}" \
          "${@}"
        }
    }
    # should only run if we did _not_ just set up dnf
    [ "$(type -t yum)" == "function" ] || {
      echo "using yum for yum calls" 1>&2
      yum() {
        # manually set release version
        # into the chroot
        # using a config we made
        # with flags as called
        sudo yum \
          --releasever="${release}" \
          --installroot="${rootdir}" \
          -c "${yumconf}" \
          "${@}"
      }
    }
  }

  # let's go!
  rootdir=$(mktemp -d)
  conftar=$(mktemp --tmpdir conf.XXX.tar)

  echo "building chroot tarball expecting system package manager ${packagemanager}" 1>&2
  echo "target system is ${distribution}-${release}-${arch}" 1>&2

  case "${packagemanager}" in
    yum|dnf|zyp)
      # init rpm, add gpg keys and release rpm
      echo "initializing RPM database with system RPM" 1>&2
      rpm --initdb
      echo "importing GPG keys" 1>&2
      for gpg in "${gpg_keydir}"/* ; do
        rpm --import "${gpg}"
      done
      echo "installing base packages from configdir" 1>&2
      rpm -iv --nodeps "${subdir}/*.rpm"

      centos_ver=$(rpm -q --qf "%{VERSION}" centos-release || true)

      echo "installing rpm repository definitions" 1>&2
      repos_d=( "${subdir}/yum.repos.d"/*.repo )
      if [ -e "${repos_d[0]}" ] ; then
        for f in "${repos_d[@]}" ; do
          b="${f##*/}"
          sudo install -D -m644 "${f}" "${rootdir}/etc/yum.repos.d/${b}"
          # copy the zypper config over here if we're going to use that
          [ "${packagemanager}" == "zyp" ] && sudo install -D -m644 "${f}" "${rootdir}/etc/zypp/repos.d/${b}"
        done
      fi
      [ "${ADDITIONAL_CONFIG_DIR:-}" ] && {
        repos2_d=( "${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/yum.repos.d"/*.repo )
        # if we have an additional config dir, plug in overrides now.
        if [ -e "${repos2_d[0]}" ] ; then
          for f in "${repos2_d[@]}" ; do
            b="${f##*/}"
            sudo install -D -m644 "${f}" "${rootdir}/etc/yum.repos.d/${b}"
            # copy the zypper config over here if we're going to use that
            [ "${packagemanager}" == "zyp" ] && sudo install -D -m644 "${f}" "${rootdir}/etc/zypp/repos.d/${b}"
          done
        fi
        # if we have a stage2 here, copy all of that now plz.
        add_stage2_yum="${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/yum.repos.d/stage2"
        add_stage2_yumconf=( "${add_stage2_yum}"/*.repo )
        [ -e "${add_stage2_yumconf[0]}" ] && {
          sudo mkdir -p -m644   "${rootdir}/etc/yum.repos.d/stage2"
          sudo install -D -m644 "${add_stage2_yumconf[@]}" "${rootdir}/etc/yum.repos.d/stage2/"
        }
      }

      echo "configuring system package manager chain to install in chroot" 1>&2
      case "${distribution}" in
        centos*)
          inst_packages=(@Base yum yum-plugin-ovl yum-utils centos-release)
          # https://lists.centos.org/pipermail/centos-devel/2018-March/016542.html
          sudo mkdir -p "${rootdir}/etc/yum/vars"
          __centos_contentdir='centos'
          [ "${arch}" != 'x86_64' ] && __centos_contentdir='altarch'
          echo "${__centos_contentdir}" | sudo tee "${rootdir}/etc/yum/vars/contentdir" > /dev/null
        ;;
        fedora*)
          inst_packages=("@Minimal Install" dnf fedora-release fedora-release-notes fedora-gpg-keys)
        ;;
        opensuse*)
          inst_packages=(bash glibc rpm zypper)
        ;;
      esac
      case "${centos_ver}" in
        5) sed -e 's/,nocontexts//' < config/yum-common.conf | sudo tee "${rootdir}/etc/yum.conf" > /dev/null
           inst_packages=(@Base yum yum-utils centos-release centos-release-notes) ;;
        *)
          sudo cp config/yum-common.conf "${rootdir}/etc/yum.conf" ;;
      esac
      # let yum do the rest of the lifting
      sudo rm -rf /var/tmp/yum-* /var/cache/yum/*
      yumconf=$(mktemp --tmpdir yum.XXXX.conf)
      sudo cp "${rootdir}/etc/yum.conf" "${yumconf}"
      printf 'reposdir=%s\n' "${rootdir}/etc/yum.repos.d" >> "${yumconf}"

      echo "installing base package dependencies in chroot using host manager" 1>&2
      yum repolist -v
      yum install -y "${inst_packages[@]}"

      echo "configuring ostree-compatible rpm db path for chroot" 1>&2
      # wire the rpmdb move here...
      [ "${packagemanager}" != "zyp" ] && {
        # see http://lists.rpm.org/pipermail/rpm-maint/2017-October/006681.html - moving the rpm dbs out of /var/lib/rpm
        target_rpmdbdir="/usr/share/rpm" # ostree-alike rpmdb dir
        sudo mkdir -p "${rootdir}/etc/rpm"
        printf '%%_dbpath\t\t%s\n' "${target_rpmdbdir}" | sudo tee -a "${rootdir}/etc/rpm/macros"
      }
    ;;
    apt)
      keyring=( "${subdir}/gpg-keys"/*.gpg )
      debootstrap_args="--foreign --merged-usr ${release}"
      case "${release}" in
        precise|trusty|xenial) debootstrap_args="--foreign --no-merged-usr ${release}"
      esac

      echo "installing system using host debootstrap" 1>&2
      debootstrap --keyring="${keyring[0]}" ${debootstrap_args} || true

      echo "configuring essential packages for in-docker operation" 1>&2
      sudo mkdir -p --mode=0755 "${rootdir}/var/lib/resolvconf" && sudo touch "${rootdir}/var/lib/resolvconf/linkified"

      echo "installing sources.list files from config directories" 1>&2
      [ -f "${subdir}/sources.list" ] && sudo install -m644 "${subdir}/sources.list" "${rootdir}/apt-sources.list"
      [ "${ADDITIONAL_CONFIG_DIR:-}" ] && {
        [ -f "${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/sources.list" ] && \
          sudo install -m644 "${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/sources.list" "${rootdir}/apt-sources.list"
      }

      echo "installing GPG keyrings" 1>&2
      case "${distribution}" in
        ubuntu*) sudo mkdir -p --mode=0755 "${rootdir}/usr/share/keyrings" && sudo install -m644 "${keyring[0]}" "${rootdir}/usr/share/keyrings/ubuntu-archive-keyring.gpg" ;;
      esac
    ;;
  esac

  [ -f "${rootdir}/etc/machine-id" ] && {
    echo "erasing /etc/machine-id in chroot" 1>&2
    : | sudo tee "${rootdir}/etc/machine-id"
  }

  echo "creating raw distribution tarball ${distribution}-${release}-${arch}.tar"
  # I need sudo for _read_ permissions, but you can own this fine.
  # shellcheck disable=SC2024
  sudo tar cp '--exclude=./dev*' -C "${rootdir}" . > "${distribution}-${release}-${arch}.tar"

  # create config tar
  echo "creating in-docker configuration files" 1>&2
  scratch=$(mktemp -d --tmpdir "$(basename "$0")".XXXXXX)
  mkdir -p             "${scratch}"/etc/{sysconfig,stamps.d}
  chmod a+rx           "${scratch}"/etc
  chmod a+rx           "${scratch}"/etc/{sysconfig,stamps.d}
  ln -s /proc/mounts   "${scratch}"/etc/mtab
  case "${packagemanager}" in
    yum)
      mkdir -p --mode=0755 "${scratch}"/var/cache/yum
      printf 'NETWORKING=yes\nHOSTNAME=localhost.localdomain\n' > "${scratch}"/etc/sysconfig/network
    ;;
  esac
  cp       startup.sh  "${scratch}"/startup
  mkdir -p --mode=0755 "${scratch}"/var/cache/ldconfig
  printf '%s\n' "${timestamp}"                              > "${scratch}/etc/stamps.d/base-build.stamp"
  printf '%s\n' "${coderev}"                                > "${scratch}/etc/stamps.d/base-code.stamp"
  printf '127.0.0.1   localhost localhost.localdomain\n'    > "${scratch}/etc/hosts"
  tar --numeric-owner --group=0 --owner=0 -c -C "${scratch}" --files-from=- -f "${conftar}" 2>/dev/null << EOA || true
./etc/mtab
./etc/hosts
./etc/stamps.d/base-build.stamp
./etc/stamps.d/base-code.stamp
./etc/sysconfig/network
./var/cache/yum
./var/cache/ldconfig
./startup
EOA

  # uncompress dev tar
  devtar=$(mktemp --tmpdir dev.XXX.tar)
  zcat "${devtgz}" > "${devtar}"

  rpmdbfiles=$(mktemp --tmpdir "$(basename "$0")".XXXXXX)

  # ubuntu/debian do stupid things to rpm.
  # shellcheck disable=SC1091
  os_like=$(. /etc/os-release ; echo "${ID_LIKE:-}")
  case "${os_like}" in
    debian) rpmdbdir="${HOME}/.rpmdb" ;;
    *)      rpmdbdir="/var/lib/rpm" ;;
  esac

  case "${packagemanager}" in
    yum|dnf)
      echo "performing rpm db export from host rpm databases" 1>&2
      # use this for rpmdb extraction
      tar --list --file="${distribution}-${release}-${arch}.tar" | \
       grep "^.${rpmdbdir}" | grep -v '/$' | tee "${rpmdbfiles}" > /dev/null

      rpmdb_dump="/usr/lib/rpm/rpmdb_dump"
      [ -e "${rpmdb_dump}" ] || {
        libdb="$(ldd "$(which rpm)"|grep libdb|cut -d= -f1)"
        libdb="${libdb#"${libdb%%[![:space:]]*}"}"
        libdb="${libdb%"${libdb##*[![:space:]]}"}"
        libdb="${libdb#*-}"
        libdb="${libdb%.so}"
        rpmdb_dump="db${libdb}_dump"
      }
      rpmdb_extract_dir=$(mktemp -d --tmpdir "$(basename "$0")".XXXXXX)
      rpmdb_dumpfiles=$(mktemp --tmpdir "$(basename "$0")".rpmdbdump.XXXXXX)
      # first, pry the rpmdb out.
      tar -C "${rpmdb_extract_dir}" --extract --file="${distribution}-${release}-${arch}".tar --files-from="${rpmdbfiles}"
      mkdir -p "${rpmdb_extract_dir}${target_rpmdbdir}"
      # convert db files to dump files
      for x in "${rpmdb_extract_dir}${rpmdbdir}"/* ; do
        dumpfile="$(basename "${x}").dump"
        "${rpmdb_dump}" "${x}" > "${rpmdb_extract_dir}${target_rpmdbdir}/${dumpfile}"
        echo ".${target_rpmdbdir}/${dumpfile}" >> "${rpmdb_dumpfiles}"
        rm "${x}"
      done

      tar --numeric-owner --group=0 --owner=0 -C "${rpmdb_extract_dir}" --create \
       --file="${distribution}-${release}-${arch}"-rpmdb.tar --files-from=- < "${rpmdb_dumpfiles}"
    ;;
  esac

  echo "deleting unwanted or overriden files from chroot tarball" 1>&2
  tar --delete --file="${distribution}-${release}-${arch}".tar --files-from=- << EOA 2>/dev/null || true
./etc/mtab
./usr/lib/locale
./usr/share/locale
./lib/gconv
./lib64/gconv
./bin/localedef
./sbin/build-locale-archive
./usr/share/man
./usr/share/doc
./usr/share/info
./usr/share/gnome/help
./usr/share/cracklib
./usr/share/i18n
./var/cache/yum
./sbin/sln
./var/cache/ldconfig
./etc/ld.so.cache
./etc/sysconfig/network
./etc/hosts
./etc/hosts.rpmnew
./etc/yum.conf.rpmnew
./etc/yum/yum.conf
./builddir
".${rpmdbdir}"
$(cat "${rpmdbfiles}")
EOA

  # bring it all together
  echo "adding device and configuration tarballs to chroot tarball" 1>&2
  tar --concatenate --file="${distribution}-${release}-${arch}".tar "${devtar}"
  tar --concatenate --file="${distribution}-${release}-${arch}".tar "${conftar}"
  case "${packagemanager}" in
    yum|dnf)
      echo "adding rpm database export to chroot tarball" 1>&2
      tar --concatenate --file="${distribution}-${release}-${arch}.tar" \
        "${distribution}-${release}-${arch}-rpmdb.tar"
      rm "${distribution}-${release}-${arch}-rpmdb.tar"
    ;;
  esac
}

docker_init () {
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"
  echo "importing chroot tarball" 1>&2
  docker import "${distribution}-${release}-${arch}.tar" "pre/${distribution}-${release}-${arch}"
  rm "${distribution}-${release}-${arch}.tar"

  echo "running initial docker setup" 1>&2
  docker run -i --name "setup_${distribution}-${release}-${arch}" -t "pre/${distribution}-${release}-${arch}" /startup

  # FIXME dropping the architecture right here for now
  echo "importing docker-ready image" 1>&2
  docker export "setup_${distribution}-${release}-${arch}" | docker import - "build/${distribution}-${release}"
  docker rm "setup_${distribution}-${release}-${arch}"
  docker rmi "pre/${distribution}-${release}-${arch}"

  echo "checking for immediate package updates in image - verifying package manager works" 1>&2
  docker_check "build/${distribution}-${release}" "${packagemanager}" && {
    docker tag "build/${distribution}-${release}" "stage2/${distribution}-${release}"
    docker rmi "build/${distribution}-${release}"
  }
}

docker_check () {
  local packagemanager image
  image="${1}"
  packagemanager="${2}"

  echo "checking for package updates in ${image} using ${packagemanager}" 1>&2
  case "${packagemanager}" in
    yum|dnf) docker run --rm=true "${image}" "${packagemanager}" check-update ;;
    zyp) docker run --rm=true "${image}" zypper patch-check ;;
    apt) docker run --rm=true "${image}" bash -ec '{ export TERM=dumb ; apt-get -q update && apt-get dist-upgrade --assume-no; }' ;;
    *)   echo "don't know how to ${packagemanager}" 1>&2 ; exit 1 ;;
  esac
}

check_existing () {
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"

  if [ -z "${DOCKER_SINK:-}" ] ; then
    echo "DOCKER_SINK unset, cannot use cache - no publishing reference!" 1>&2
    return 1
  else
    [ "${FORCE_BUILD:-}" ] && return 1
    docker_check "${DOCKER_SINK}/${distribution}:${release}" "${packagemanager}" && \
      docker tag "${DOCKER_SINK}/${distribution}:${release}" "final/${distribution}:${release}"
  fi
}

build_pki_layer () {
  docker build -f "pki/Dockerfile" -t "pki" pki
}

add_layers () {
  local packagemanager distribution release subdir stage2name additional_rpms dist_addstr
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"
  additional_rpms=()

  build_pki_layer

  stage2name=$(docker images "stage2/${distribution}-${release}" --format "{{.Repository}}")

  if [ ! -z  "${stage2name}" ] ; then
    if [ -f "${subdir}/Dockerfile" ] ; then
      case "${packagemanager}" in
        yum|dnf|zyp)
          dist_addstr="ADDITIONAL_${distribution}_${release}_RPM_PACKAGES"
          dist_addstr="${dist_addstr^^}"
          [ "${ADDITIONAL_RPM_PACKAGES:-}" ] && additional_rpms+=("${ADDITIONAL_RPM_PACKAGES}")
          [ "${!dist_addstr:-}" ]            && additional_rpms+=("${!dist_addstr}")
        ;;
      esac
      IFS=' ' docker build -f "${subdir}/Dockerfile" -t "final/${distribution}:${release}" --build-arg ADDITIONAL_RPM_PACKAGES="${additional_rpms[*]}" .
    else
      docker tag "stage2/${distribution}-${release}" "final/${distribution}:${release}"
    fi
    docker rmi "stage2/${distribution}-${release}"
  fi
}

if [ -z "${1+x}" ] ; then
  # build everything!
  for d in config/*/* ; do
   check_existing "${d}" || {
     create_chroot_tarball "${d}"
     docker_init "${d}"
     add_layers "${d}"
   }
  done
else
  check_existing "${1}" || {
  create_chroot_tarball "${1}"
  docker_init "${1}"
  add_layers "${1}"
  }
fi

