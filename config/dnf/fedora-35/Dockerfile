FROM stage2/fedora-35

ARG ADDITIONAL_RPM_PACKAGES=""
ENV ADDITIONAL_RPM_PACKAGES=${ADDITIONAL_RPM_PACKAGES}

RUN bash -c 'rpmgpg=( /etc/pki/rpm-gpg/RPM-GPG-KEY* /etc/pki/rpm-gpg/*.asc) ; \
      for g in "${rpmgpg[@]}" ; do \
        [ -e "${g}" ] && rpm --import "${g}" ; \
        true ; \
      done'

RUN bash -c '[ "${ADDITIONAL_RPM_PACKAGES}" ] && /usr/lib/untrustedhost/scripts/pkginst.sh ${ADDITIONAL_RPM_PACKAGES} || true'
