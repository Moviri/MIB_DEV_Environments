FROM bigtop/puppet:trunk-rockylinux-8

ENV container=docker

RUN setenforce 0
RUN sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

RUN dnf clean all -y && dnf update -y

RUN dnf install -y sudo openssh-server openssh-clients 
RUN dnf install -y which iproute net-tools less vim-enhanced
RUN dnf install -y initscripts wget curl tar unzip git
RUN dnf install -y python3 python3-distro python3-psycopg2
RUN dnf install -y chrony

RUN sed -i 's/^enabled=0/enabled=1/' /etc/yum.repos.d/Rocky-Devel.repo

RUN dnf clean all -y && rm -rf /var/cache/dnf

RUN ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
RUN systemctl enable sshd

ENV HOME=/root

CMD ["/usr/sbin/init"]