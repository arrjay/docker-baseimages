#!/usr/bin/env bash

set -x

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  ts=$(docker run --rm=true "${img}" cat /etc/stamps.d/base-build.stamp)
  cr=$(docker run --rm=true "${img}" cat /etc/stamps.d/base-code.stamp)
  case "${dest}" in
    ubuntu:*)
      vnum=$(docker run --rm=true "${img}" bash -c '. /etc/os-release && echo $VERSION_ID')
      docker tag "${img}" "${DOCKER_SINK}/ubuntu:${vnum}"
      [ "${NOPUSH}" ] || docker push "${DOCKER_SINK}/ubuntu:${vnum}"
    ;;
  esac
  docker tag "${img}" "${DOCKER_SINK}/${dest}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}.${cr}"
  [ "${NOPUSH}" ] || {
    docker push "${DOCKER_SINK}/${dest}"
    docker push "${DOCKER_SINK}/${dest}.${ts}"
    docker push "${DOCKER_SINK}/${dest}.${ts}.${cr}"
  }
  docker rmi "${img}"
done

