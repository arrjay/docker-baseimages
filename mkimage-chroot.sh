#!/usr/bin/env bash

set -eux
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

# reset umask
umask 0022

# check for device file archive
if [ ! -f "${devtgz}" ] ; then
  printf 'missing the /dev tar archive (run sudo mkdev.sh)\n' 1>&2
  exit 2
fi

# create a scratch directory to use for working files
wkdir=$(env TMPDIR=/var/tmp mktemp -d)
export TMPDIR="${wkdir}"

__cleanup () {
  [ -z "${NOCLEAN:-}" ] && sudo rm -rf "${wkdir}"
}

trap __cleanup EXIT ERR

sudo () { env "$@"; }
# if we're not root, bring sudo to $sudo
[ "$(id -u)" != "0" ] && sudo () { command sudo env "$@"; }

create_chroot_tarball () {
  local packagemanager distribution release subdir debootstrap
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
  local deboostrap_file
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

  # mock out commands via function overload here - which is exactly what we want, but drives shellcheck batty.
  # shellcheck disable=SC2032,SC2033
  rpm() { sudo rpm --root "${rootdir}" "${@}"; }
  [ -f "${subdir}/arch" ] && read -r arch < "${subdir}/arch"
  debootstrap() { sudo DEBOOTSTRAP_DIR="$(pwd)/debootstrap" bash -x "${debootstrap}" --verbose --variant=minbase "--arch=${arch}" "${@}" "${rootdir}" "${UBUNTU_URI}" ; }
  yum() { sudo yum --releasever="${release}" --installroot="${rootdir}" -c "${yumconf}" "${@}"; }
  # if we're actually using dnf, do not install weak dependencies
  type dnf 2> /dev/null 1>&2 && yum() { sudo dnf --setopt=install_weak_deps=False --best --releasever="${release}" --installroot="${rootdir}" -c "${yumconf}" "${@}" ; }

  # let's go!
  rootdir=$(mktemp -d)
  conftar=$(mktemp --tmpdir conf.XXX.tar)

  case "${packagemanager}" in
    yum|dnf|zyp)
      # init rpm, add gpg keys and release rpm
      rpm --initdb
      for gpg in "${gpg_keydir}"/* ; do
        rpm --import "${gpg}"
      done
      rpm -iv --nodeps "${subdir}/*.rpm"
      centos_ver=$(rpm -q --qf "%{VERSION}" centos-release || true)
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
      case "${distribution}" in
        centos*)
          inst_packages=(@Base yum yum-plugin-ovl yum-utils centos-release)
          # https://lists.centos.org/pipermail/centos-devel/2018-March/016542.html
          sudo mkdir -p "${rootdir}/etc/yum/vars"
          [ "${arch}" == 'x86_64' ]  && echo 'centos' | sudo tee "${rootdir}/etc/yum/vars/contentdir" || echo 'altarch' | sudo tee "${rootdir}/etc/yum/vars/contentdir"
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
      yum repolist -v
      yum install -y "${inst_packages[@]}"
      # wire the rpmdb move here...
      [ "${packagemanager}" != "zyp" ] && {
        # see http://lists.rpm.org/pipermail/rpm-maint/2017-October/006681.html - moving the rpm dbs out of /var/lib/rpm
        target_rpmdbdir="/usr/share/rpm" # ostree-alike rpmdb dir
        sudo mkdir -p "${rootdir}/etc/rpm"
        printf '%%_dbpath\t\t%s\n' "${target_rpmdbdir}" | sudo tee -a "${rootdir}/etc/rpm/macros"
      }
    ;;
    apt)
      debootstrap=$(which debootstrap)
      keyring=( "${subdir}/gpg-keys"/*.gpg )
      debootstrap_args="--foreign --merged-usr ${release}"
      case "${release}" in
        precise|trusty|xenial) debootstrap_args="--foreign ${release}"
      esac
      debootstrap --keyring="${keyring[0]}" ${debootstrap_args} || true
      sudo mkdir -p --mode=0755 "${rootdir}/var/lib/resolvconf" && sudo touch "${rootdir}/var/lib/resolvconf/linkified"
      [ -f "${subdir}/sources.list" ] && sudo install -m644 "${subdir}/sources.list" "${rootdir}/apt-sources.list"
      [ "${ADDITIONAL_CONFIG_DIR:-}" ] && {
        [ -f "${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/sources.list" ] && \
          sudo install -m644 "${ADDITIONAL_CONFIG_DIR}/${subdir#config/}/sources.list" "${rootdir}/apt-sources.list"
      }
      case "${distribution}" in
        ubuntu*) sudo mkdir -p --mode=0755 "${rootdir}/usr/share/keyrings" && sudo install -m644 "${keyring[0]}" "${rootdir}/usr/share/keyrings/ubuntu-archive-keyring.gpg" ;;
      esac
    ;;
  esac

  [ -f "${rootdir}/etc/machine-id" ] && : | sudo tee "${rootdir}/etc/machine-id"

  # I need sudo for _read_ permissions, but you can own this fine.
  # shellcheck disable=SC2024
  sudo tar cp '--exclude=./dev*' -C "${rootdir}" . > "${distribution}-${release}.tar"

  # create config tar
  scratch=$(mktemp -d --tmpdir "$(basename "$0")".XXXXXX)
  mkdir -p             "${scratch}"/etc/sysconfig
  chmod a+rx           "${scratch}"/etc
  chmod a+rx           "${scratch}"/etc/sysconfig
  ln -s /proc/mounts   "${scratch}"/etc/mtab
  case "${packagemanager}" in
    yum)
  mkdir -p --mode=0755 "${scratch}"/var/cache/yum
    ;;
  esac
  cp       startup.sh  "${scratch}"/startup
  mkdir -p --mode=0755 "${scratch}"/var/cache/ldconfig
  printf 'NETWORKING=yes\nHOSTNAME=localhost.localdomain\n' > "${scratch}"/etc/sysconfig/network
  printf '127.0.0.1   localhost localhost.localdomain\n'    > "${scratch}"/etc/hosts
  tar --numeric-owner --group=0 --owner=0 -c -C "${scratch}" --files-from=- -f "${conftar}" << EOA || true
./etc/mtab
./etc/hosts
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
  os_like=$(. /etc/os-release ; echo ${ID_LIKE:-})
  case "${os_like}" in
    debian) rpmdbdir="${HOME}/.rpmdb" ;;
    *)      rpmdbdir="/var/lib/rpm" ;;
  esac

  case "${packagemanager}" in
    yum|dnf)
      # use this for rpmdb extraction
      tar --list --file="${distribution}-${release}.tar" | grep "^.${rpmdbdir}" | grep -v '/$' | tee "${rpmdbfiles}"

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
    tar -C "${rpmdb_extract_dir}" --extract --file="${distribution}-${release}".tar --files-from="${rpmdbfiles}"
    mkdir -p "${rpmdb_extract_dir}${target_rpmdbdir}"
    # convert db files to dump files
    for x in "${rpmdb_extract_dir}${rpmdbdir}"/* ; do
      dumpfile="$(basename "${x}").dump"
      "${rpmdb_dump}" "${x}" > "${rpmdb_extract_dir}${target_rpmdbdir}/${dumpfile}"
      echo ".${target_rpmdbdir}/${dumpfile}" >> "${rpmdb_dumpfiles}"
      rm "${x}"
    done

    tar --numeric-owner --group=0 --owner=0 -C "${rpmdb_extract_dir}" --create --file="${distribution}-${release}"-rpmdb.tar --files-from=- < "${rpmdb_dumpfiles}"
    ;;
  esac

  tar --delete --file="${distribution}-${release}".tar --files-from=- << EOA || true
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
  tar --concatenate --file="${distribution}-${release}".tar "${devtar}"
  tar --concatenate --file="${distribution}-${release}".tar "${conftar}"
  case "${packagemanager}" in
    yum|dnf) tar --concatenate --file="${distribution}-${release}.tar" "${distribution}-${release}-rpmdb.tar" && rm "${distribution}-${release}-rpmdb.tar" ;;
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
  docker import "${distribution}-${release}.tar" "pre/${distribution}-${release}"
  rm "${distribution}-${release}.tar"
  docker run -i --name "setup_${distribution}-${release}" -t "pre/${distribution}-${release}" /startup
  docker export "setup_${distribution}-${release}" | docker import - "build/${distribution}-${release}"
  docker rm "setup_${distribution}-${release}"
  docker rmi "pre/${distribution}-${release}"

  docker_check "build/${distribution}-${release}" "${packagemanager}" && {
    docker tag "build/${distribution}-${release}" "stage2/${distribution}-${release}"
    docker rmi "build/${distribution}-${release}"
  }
}

docker_check () {
  local packagemanager image
  image="${1}"
  packagemanager="${2}"

  case "${packagemanager}" in
    yum|dnf) docker run --rm=true "${image}" "${packagemanager}" check-update ;;
    zyp) docker run --rm=true "${image}" zypper patch-check ;;
    apt) docker run --rm=true "${image}" bash -ec '{ export TERM=dumb ; apt-get -q update && apt-get dist-upgrade --assume-no; }' ;;
    *)   echo "don't know how to ${packagemanager}" 1>&2 ; exit 1 ;;
  esac
}

check_existing () {
  [ "${FORCE_BUILD:=}" ] && return 1
  local packagemanager distribution release subdir
  subdir="${1}"
  packagemanager="${subdir%/*}"
  packagemanager="${packagemanager#*/}"
  distribution="${subdir#*${packagemanager}/}"
  release="${distribution#*-}"
  distribution="${distribution%-${release}}"

  if [ "${DOCKER_SINK:=''}" ] ; then
    docker_check "${DOCKER_SINK}/${distribution}:${release}" "${packagemanager}" && \
      docker tag "${DOCKER_SINK}/${distribution}:${release}" "final/${distribution}:${release}"
  else
    docker rmi -f "${DOCKER_SINK}/${distribution}:${release}"
    return 1
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

