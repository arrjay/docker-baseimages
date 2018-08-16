FROM stage2/centos-7

ARG ADDITIONAL_RPM_PACKAGES=""
ENV ADDITIONAL_RPM_PACKAGES=${ADDITIONAL_RPM_PACKAGES}

RUN yum -y install epel-release

ADD pki/rpm-gpg /etc/pki/rpm-gpg
ADD yum.repos.d /etc/yum.repos.d

RUN yum -y install tar

RUN bash -c '[ "${ADDITIONAL_RPM_PACKAGES}" ] && yum -y install ${ADDITIONAL_RPM_PACKAGES} || true'
