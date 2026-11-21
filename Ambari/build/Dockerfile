# Bigtop 3.3.0 Rocky Linux 8 x86_64 build toolchain, verified 2026-09-29.
FROM bigtop/slaves:3.3.0-rockylinux-8@sha256:0fcd3a3afaa2e55859a669f2ac44e977aa7917a93f85b780ded91d80677cfdb9

USER root
RUN dnf install -y java-17-openjdk-devel python3-devel createrepo_c curl \
    && dnf clean all

COPY container-build.sh /opt/ambari-build/container-build.sh
COPY apply-bigtop-patches.sh /opt/ambari-build/apply-bigtop-patches.sh
COPY prepare-bigtop-select.py /opt/ambari-build/prepare-bigtop-select.py
COPY patches/ /opt/ambari-build/patches/
WORKDIR /work
ENTRYPOINT ["/bin/bash", "/opt/ambari-build/container-build.sh"]
