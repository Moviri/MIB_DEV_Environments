





RUN wget -nv http://public-repo-1.hortonworks.com/ambari/centos7/2.x/updates/2.7.4.0/ambari.repo -O /etc/yum.repos.d/ambari.repo
RUN yum update -y && yum -y install ambari-server
RUN yum clean all && rm -rf /var/cache/yum
RUN mkdir -p /usr/share/java/
# Mysql connector that could be used by agent
# RUN wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-8.0.19-1.el7.noarch.rpm
# RUN /usr/bin/rpm -i ./mysql-connector-java-8.0.19-1.el7.noarch.rpm
# RUN rm ./mysql-connector-java-8.0.19-1.el7.noarch.rpm
# RUN ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java-8.0.19.jar
#Postgres connector
RUN wget https://jdbc.postgresql.org/download/postgresql-42.2.9.jar
RUN /usr/bin/mv ./postgresql-42.2.9.jar /usr/share/java/postgresql-42.2.9.jar && chmod 644 /usr/share/java/postgresql-42.2.9.jar
RUN ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-42.2.9.jar
WORKDIR /var/lib/ambari-server/resources/
RUN wget http://public-repo-1.hortonworks.com/ARTIFACTS/jdk-8u112-linux-x64.tar.gz
RUN wget http://public-repo-1.hortonworks.com/ARTIFACTS/jce_policy-8.zip
WORKDIR /root
# NOTICE !
COPY ./init-server.sh /root/init.sh
RUN chmod 0751 /root/init.sh
RUN chown root:root /root/init.sh
RUN echo -e "\\n/root/init.sh" >> /etc/rc.d/rc.local
RUN chmod +x /etc/rc.d/rc.local
RUN /usr/bin/systemctl enable rc-local.service
EXPOSE 5432 8440 8441 8440