#!/usr/bin/env bash

set -eux

# first...who am I? what is this?
id
env

# stub in/out docker or libpod equivalents
[ "${USE_BUILDAH:-}" == true ] && {
  _buildah_status () {
    buildah images
    buildah containers
  }

  _podman_images () {
    podman images
  }
} || {
  _buildah_status () {
    docker images
    docker ps -a
  }

  _podman_images () {
    docker images
  }
}

_podman_images
_buildah_status

# tuneables
[ "${UBUNTU_URI:=}" ] || UBUNTU_URI=https://mirrors.kernel.org/ubuntu/

__warn_msg () { echo "${@}" 1>&2 ; }

__fail_msg () { __warn_msg "${@}" ; return 1 ; }

# check for needed binaries
__check_progs () {
  local prog proglist rc
  rc=0
  proglist=("${@}")
  for prog in "${proglist[@]}" ; do
    type "${prog}" > /dev/null 2>&1 || { __warn_msg "missing ${prog}" ; rc=126 ; }
  done
  return "${rc}"
}

# get checkout directory git revision information
__get_cr () {
  local cr
  # initial shortrev
  cr="$(git rev-parse --short HEAD)"
  # check for uncommitted files
  { git diff-index --quiet --cached HEAD -- &&
    # check for extra files
    git diff-files --quiet ; } || cr="${cr}-DIRTY"
  echo "${cr}"
}

# check for needed binaries now
__check_progs git date env sleep mktemp docker tar tee wget || exit "${?}"

# we emulate sudo if we're already root
sudo () { env "$@"; }

# if we're not root, bring sudo to $sudo
# also, check for sudo
{
  [ "$(id -u)" != "0" ] && {
    __warn_msg "you are not root, wrapping commands in sudo..."
    __check_progs sudo || exit "${?}"
    sudo () { command sudo env "$@"; }
  } ;
} || echo "your are already root, 'sudo' is env in this script."

# derive build stamps here
CODEREV="$(__get_cr)"
TIMESTAMP="$(date +%s)"

case "${CODEREV}" in
  *-DIRTY) __warn_msg "WARNING: git tree is dirty, sleeping 5 seconds for running confirmation."
           sleep 5
           ;;
esac

echo "building ${CODEREV} at ${TIMESTAMP}"

# create a scratch directory to use for working files
WORKDIR="$(env TMPDIR=/var/tmp mktemp -d)"
export TMPDIR="${WORKDIR}"

echo "using ${UBUNTU_URI} as debootstrap mirror."

__cleanup () {
  echo "working directory was ${WORKDIR}" 1>&2
  [ -z "${NOCLEAN:-}" ] && { __warn_msg "removing workdir" ; sudo rm -rf "${WORKDIR}" ; }
}

trap __cleanup EXIT ERR

# build an image using our inc'd debootstrap
debootstrap () {
  local rootdir release rc
  rootdir="$(mktemp -d)"
  release="${1}"
  sudo DEBOOTSTRAP_DIR="${PWD}/vendor/debootstrap" \
   bash -x "${PWD}/vendor/debootstrap/debootstrap" \
    --verbose --variant=minbase --arch=amd64 \
    --foreign --merged-usr \
    --keyring="${PWD}/ubuntu-archive-keyring.gpg" \
    ${release} \
    ${rootdir} \
    ${UBUNTU_URI} 1>&2
  rc="${?}"
  echo "${rootdir}"
  return "${rc}"
}

temp_chroot="$(debootstrap bionic)"

# insert the build stamps now
sudo mkdir -p "${temp_chroot}/etc/facter/facts.d"
{
  echo "base_image_coderev=${CODEREV}"
  echo "base_image_timestamp=${TIMESTAMP}"
} | sudo tee -a "${temp_chroot}/etc/facter/facts.d/baseimage.txt"

# hand to docker
sudo tar cpf - -C "${temp_chroot}" . | docker import - build/pre

# run finalization *in* a docker container
docker build -t build/init docker

# and create an instance for export
docker run "--name=image-${CODEREV}-${TIMESTAMP}" build/init true

# export into a new image
docker export "image-${CODEREV}-${TIMESTAMP}" | docker import - build/release

# clean up the old images
docker rmi -f build/init
docker rmi -f build/pre

# clean up the old container
docker rm -f "image-${CODEREV}-${TIMESTAMP}"
