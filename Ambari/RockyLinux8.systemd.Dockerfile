FROM rockylinux:8

ENV container=docker

RUN echo "Setting up root password to \"ambari\""
RUN echo "root:ambari" | chpasswd

RUN dnf clean all -y && dnf update -y

RUN dnf install -y sudo systemd openssh-server openssh-clients 
RUN dnf install -y which iproute net-tools less vim-enhanced
RUN dnf install -y initscripts wget curl tar unzip git
RUN dnf install -y python3 python3-distro python3-psycopg2
RUN dnf install -y chrony

RUN sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/Rocky-Devel.repo

RUN dnf clean all -y && rm -rf /var/cache/dnf

RUN ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
RUN cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
RUN systemctl enable sshd

ENV HOME=/root

RUN (cd /lib/systemd/system/sysinit.target.wants/; for i in *; do [ "$i" = systemd-tmpfiles-setup.service ] || rm -f $i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*; \
rm -f /etc/systemd/system/*.wants/*; \
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*; \
rm -f /lib/systemd/system/anaconda.target.wants/*;

RUN /usr/bin/systemctl enable chronyd.service
VOLUME [ "/sys/fs/cgroup" ]

CMD ["/usr/sbin/init"]