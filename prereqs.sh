#!/usr/bin/env bash

# install any missing prereqs - assumes ubuntu 18.04 from upstream

[ -f /etc/apt/sources.list.d/projectatomic-ubuntu-ppa-bionic.list ] || add-apt-repository -y ppa:projectatomic/ppa

type buildah || apt-get install -q -y buildah
type podman  || apt-get install -q -y podman
