FROM stage2/ubuntu-bionic

RUN update-ca-certificates

RUN apt-get update && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install \
     xz-utils && \
    apt-get clean all && rm -rf /var/lib/apt/lists/*
