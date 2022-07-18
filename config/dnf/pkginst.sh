#!/usr/bin/env bash

set -ex

# convenience wrapper around dnf-y bits
dnf makecache

dnf -y install "${@}"

dnf clean all
