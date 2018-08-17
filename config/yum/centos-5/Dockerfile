FROM stage2/centos-5

ARG ADDITIONAL_RPM_PACKAGES=""
ENV ADDITIONAL_RPM_PACKAGES=${ADDITIONAL_RPM_PACKAGES}

COPY --from=pki rpm-gpg /etc/pki/rpm-gpg

ADD pki/rpm-gpg-centos-5 /etc/pki/rpm-gpg

RUN bash -c 'rpmgpg=( /etc/pki/rpm-gpg/RPM-GPG-KEY* /etc/pki/rpm-gpg/*.asc) ; \
      for g in "${rpmgpg[@]}" ; do \
        [ -e "${g}" ] && rpm --import "${g}" ; \
        true ; \
      done'

RUN yum -q -y install curl.x86_64 epel-release && \
    rm -f /etc/yum.repos.d/epel.repo.rpmnew

RUN bash -c '[ "${ADDITIONAL_RPM_PACKAGES}" ] && yum -y install ${ADDITIONAL_RPM_PACKAGES} || true'
