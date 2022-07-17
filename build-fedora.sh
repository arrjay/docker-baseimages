#!/usr/bin/env bash

exec ./mkimage-chroot.sh config/dnf/fedora-"${FEDORA_VER}"
