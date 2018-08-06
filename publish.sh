#!/usr/bin/env bash

ts=$(date +%s)

docker images "final/*"

[ "${ARTIFACTORY_USERNAME}" ] && {
  docker login -u "${ARTIFACTORY_USERNAME}" -p "${ARTIFACTORY_PASSWORD}" docker.palantir.build
}

for img in $(docker images "final/*" --format "{{.Repository}}:{{.Tag}}") ; do
  dest="${img#final/}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}"
  docker tag "${img}" "${DOCKER_SINK}/${dest}.${ts}"
  [ "${NOPUSH}" ] || {
    docker push "${DOCKER_SINK}/${dest}"
    docker push "${DOCKER_SINK}/${dest}.${ts}"
  }
done

