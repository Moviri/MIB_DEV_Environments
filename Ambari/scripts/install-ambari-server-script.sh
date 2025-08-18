#!/bin/bash

set -ex

# ambari agent
yum install -y python3-distro
yum install -y java-17-openjdk-devel
yum install -y java-1.8.0-openjdk-devel
yum install -y ambari-agent

# ambari server
yum install -y python3-psycopg2
yum install -y ambari-server


# MySQL
yum -y install https://dev.mysql.com/get/mysql80-community-release-el8-1.noarch.rpm

yum -y install mysql-server

# Check if MySQL data directory is already initialized
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MySQL data directory"
    rm -rf /var/lib/mysql/*
    mysqld --initialize
    chown -R mysql:mysql /var/lib/mysql
else
    echo "MySQL data directory already exists, skipping initialization"
fi

# Configure MySQL if not already configured
if ! grep -q "bind-address=0.0.0.0" /etc/my.cnf.d/mysql-server.cnf; then
    echo 'bind-address=0.0.0.0' >> /etc/my.cnf.d/mysql-server.cnf
fi

systemctl start mysqld.service
systemctl enable mysqld.service

# Wait for MySQL to be ready
sleep 5
until [ -S /var/lib/mysql/mysql.sock ]; do
    echo "Waiting for MySQL socket to be created..."
    sleep 2
done
echo "MySQL socket is ready"

# Check if MySQL is already configured by testing if we can connect with the final password
if mysql -u root -pambarirootpass -e "SELECT 1;" &>/dev/null; then
    echo "MySQL is already configured, skipping setup"
else
    echo "Setting up MySQL for the first time"
    
    # Extract the most recent temporary password (get the last occurrence)
    MYSQL_ROOT_PASS=$(cat /var/log/mysql/mysqld.log | grep -i 'password is generated' | tail -1 | rev | cut -d ':' -f1 | rev | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    if [ -z "$MYSQL_ROOT_PASS" ]; then
        echo "ERROR: Could not extract MySQL temporary password from log"
        exit 1
    fi
    
    echo "Extracted password length: ${#MYSQL_ROOT_PASS}"
    
    echo "
ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY 'ambarirootpass';
CREATE USER 'root'@'%.demo.local' IDENTIFIED WITH caching_sha2_password BY 'ambarirootpass';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%.demo.local';
-- Create Ambari user and grant privileges
CREATE USER 'ambari'@'localhost' IDENTIFIED BY 'ambari';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'localhost';
CREATE USER 'ambari'@'%' IDENTIFIED BY 'ambari';
GRANT ALL PRIVILEGES ON *.* TO 'ambari'@'%';

-- Create required databases
CREATE DATABASE ambari CHARACTER SET utf8 COLLATE utf8_general_ci;
CREATE DATABASE hive;
CREATE DATABASE ranger;
CREATE DATABASE rangerkms;

-- Create service users
CREATE USER 'hive'@'%' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON hive.* TO 'hive'@'%';

CREATE USER 'ranger'@'%' IDENTIFIED BY 'ranger';
GRANT ALL PRIVILEGES ON *.* TO 'ranger'@'%' WITH GRANT OPTION;

CREATE USER 'rangerkms'@'%' IDENTIFIED BY 'rangerkms';
GRANT ALL PRIVILEGES ON rangerkms.* TO 'rangerkms'@'%';

FLUSH PRIVILEGES;" > /root/ambari-server-setup.sql

    mysql --connect-expired-password -u root -p"${MYSQL_ROOT_PASS}" < /root/ambari-server-setup.sql
fi

mysql --connect-expired-password -uambari -pambari ambari < /var/lib/ambari-server/resources/Ambari-DDL-MySQL-CREATE.sql

# setup Ambari MySQL

wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar \
  -O /usr/share/java/mysql-connector-java.jar

ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

echo "server.jdbc.url=jdbc:mysql://localhost:3306/ambari?useSSL=true&verifyServerCertificate=false&enabledTLSProtocols=TLSv1.2" >> /etc/ambari-server/conf/ambari.properties

ambari-server setup -s \
  -j /usr/lib/jvm/java-1.8.0-openjdk \
  --ambari-java-home /usr/lib/jvm/java-17-openjdk \
  --database=mysql \
  --databasehost=localhost \
  --databaseport=3306 \
  --databasename=ambari \
  --databaseusername=ambari \
  --databasepassword=ambari


ambari-server start

