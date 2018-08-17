FROM stage2/ubuntu-trusty

COPY --from=pki ca-certificates /usr/local/share/ca-certificates/extra

RUN update-ca-certificates
