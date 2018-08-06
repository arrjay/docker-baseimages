#!/usr/bin/env bash

ts=$(date +%s)

docker images "final/*"

[ "${ARTIFACTORY_USERNAME}" ] && {
  docker login -u "${ARTIFACTORY_USERNAME}" -p "${ARTIFACTORY_PASSWORD}" docker.palantir.build
}

set -x

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  case "${dest}" in
    ubuntu:*)
      vnum=$(docker run --rm=true "${img}" lsb_release -rs)
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
done

