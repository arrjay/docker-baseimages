#!/usr/bin/env bash

apt-get -q update

# install any missing prereqs - assumes ubuntu 18.04 from upstream
[ "${USE_BUILDAH:-}" == "true" ] && {
[ -f /etc/apt/sources.list.d/projectatomic-ubuntu-ppa-bionic.list ] || {
  type add-apt-repository || apt-get install -q -y software-properties-common
  add-apt-repository -y ppa:projectatomic/ppa
  apt-get -q update
}

  type buildah || apt-get install -q -y buildah
  type podman  || apt-get install -q -y podman
} || {
  # use docker.io as shipped with Ubuntu kplzthx
  type docker || apt-get install -q -y docker.io
}
