FROM stage2/ubuntu-trusty

COPY --from=pki ca-certificates /usr/local/share/ca-certificates/extra

RUN update-ca-certificates

RUN apt-get -q -y update && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends install -q -y \
     xz-utils && \
    apt-get -q -y clean all && rm -rf /var/lib/apt/lists/*
