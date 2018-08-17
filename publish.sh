#!/usr/bin/env bash

ts=$(date +%s)

set -x

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  case "${dest}" in
    ubuntu:*)
      vnum=$(docker run --rm=true "${img}" bash -c '. /etc/os-release && echo $VERSION_ID')
      docker tag "${img}" "${DOCKER_SINK}/ubuntu:${vnum}"
      [ "${NOPUSH}" ] || docker push "${DOCKER_SINK}/ubuntu:${vnum}"
    ;;
  esac
  docker tag "${img}" "${DOCKER_SINK}/${dest}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  [ "${NOPUSH}" ] || {
    docker push "${DOCKER_SINK}/${dest}"
    docker push "${DOCKER_SINK}/${dest}.${ts}"
  }
  docker rmi "${img}"
done

