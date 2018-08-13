FROM stage2/centos-6

RUN yum -y install epel-release

ADD pki/rpm-gpg /etc/pki/rpm-gpg
ADD yum.repos.d /etc/yum.repos.d

# ?: running palantir-ssl-ca in docker is tripping on a check about docs. enable anyway.
RUN yum -y install tar palantir-ssl-ca && update-ca-trust force-enable
