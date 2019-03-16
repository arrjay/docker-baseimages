#!/usr/bin/env bash

set -ex

# convenience wrapper around apt-y bits
DEBIAN_FRONTEND=noninteractive

export DEBIAN_FRONTEND

apt-get update

apt-get install "${@}"

apt-get clean all

rm -rf /var/lib/apt/lists/*
