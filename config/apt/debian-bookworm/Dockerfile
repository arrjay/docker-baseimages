FROM stage2/debian-bookworm

RUN update-ca-certificates

RUN apt-get -q -y update && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends install -q -y \
     xz-utils && \
    apt-get -q -y clean all && rm -rf /var/lib/apt/lists/*
