#!/usr/bin/env bash

set -eu

[ "${ARTIFACTORY_USERNAME:-}" ] && {
  docker login -u "${ARTIFACTORY_USERNAME}" -p "${ARTIFACTORY_PASSWORD}" docker.palantir.build
}

set -x

ts=$(date +%s)

docker images "final/*"

[ "${CIRCLE_BRANCH:-}" ] && {
  case "${CIRCLE_BRANCH}" in
    master) : ;;
    *)      NOPUSH=1 ;;
  esac
}

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  case "${dest}" in
    ubuntu:*)
      # shellcheck disable=SC2016
      vnum=$(docker run --rm=true "${img}" bash -c '. /etc/os-release && echo $VERSION_ID')
      docker tag "${img}" "${DOCKER_SINK}/ubuntu:${vnum}"
      [ "${NOPUSH:-}" ] || docker push "${DOCKER_SINK}/ubuntu:${vnum}"
    ;;
  esac
  docker tag "${img}" "${DOCKER_SINK}/${dest}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  [ "${NOPUSH:-}" ] || {
    docker push "${DOCKER_SINK}/${dest}"
    docker push "${DOCKER_SINK}/${dest}.${ts}"
  }
done

