#!/usr/bin/env bash

set -x

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
