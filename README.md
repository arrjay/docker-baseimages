# base-docker-images

repository that makes base docker images from chroots

This repository builds docker base images from scratch for ubuntu 16.04/18.094 and centos 6/7

These images are built using artifactory as the bootstrap mirror, and for centos, include palantir RPM keying.

All images have support for Palantir CA roots.

Most of the image creation lives in `./mkimage-chroot.sh` - run in the top of the repo, it will build images from the files laid in
`./config`. Under there is a directory for each type of packaging system we support - currently `apt`, `dnf`, and `yum`.

The theory behind this system is to do _just enough work_ in the chroot to bootstrap a packaging system, then do any other base steps
inside a docker image. That is accomplished through `./startup.sh` as an initial docker entry point. The result from that container run
is then exported and re-imported as a new base docker image.

## Images exported from this repository
- `ubuntu:version` - currently `18.04` and `16.04` - this will be replaced as package updates mandate
- `ubuntu:codename` - currently `bionic` and `xenial` - this will be replaced as package updates mandate
- `centos:version` - currently `7` and `6` - this will be replaced as package updates mandate

## Persistent images
- `ubuntu:codename.TIMESTAMP` - this will have an encoding of when publish.sh ran if you need a particular image
- `centos:version.TIMESTAMP` - as with centos, this timestamp is when the publish job ran.
