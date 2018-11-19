#!/usr/bin/env bash

set +x

for img in $(sudo buildah images --json | jq -ars 'unique_by(.id)|.[].names[]|select(contains("localhost/final"))') ; do
  dest="${img#localhost/final/}"
  ts=$(sudo podman run --rm=true "${img}" cat /etc/stamps.d/base-build.stamp)
  cr=$(sudo podman run --rm=true "${img}" cat /etc/stamps.d/base-code.stamp)
  case "${dest}" in
    ubuntu:*)
      vnum=$(sudo podman run --rm=true "${img}" bash -c '. /etc/os-release && echo $VERSION_ID')
      buildah tag "${img}" "${DOCKER_SINK}/ubuntu:${vnum}"
      [ "${NOPUSH}" ] || sudo buildah push --creds "${DOCKER_USER}:${DOCKER_PASS}" "${DOCKER_SINK}/ubuntu:${vnum}" "docker://${DOCKER_SINK}/ubuntu:${vnum}"
    ;;
  esac
  sudo buildah tag "${img}" "${DOCKER_SINK}/${dest}"
  sudo buildah tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  sudo buildah tag "${img}" "${DOCKER_SINK}/${dest}.${ts}.${cr}"
  [ "${NOPUSH}" ] || {
    sudo buildah push --creds "${DOCKER_USER}:${DOCKER_PASS}" "${DOCKER_SINK}/${dest}"             "docker://${DOCKER_SINK}/${dest}"
    sudo buildah push --creds "${DOCKER_USER}:${DOCKER_PASS}" "${DOCKER_SINK}/${dest}.${ts}"       "docker://${DOCKER_SINK}/${dest}.${ts}"
    sudo buildah push --creds "${DOCKER_USER}:${DOCKER_PASS}" "${DOCKER_SINK}/${dest}.${ts}.${cr}" "docker://${DOCKER_SINK}/${dest}.${ts}.${cr}"
  }
done

