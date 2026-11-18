#!/bin/bash
set -euo pipefail

# Only the known Ambari 3.0.0 archive-build defect is repaired. Preserve the
# original launcher and do not replace a real SCM hash in a working package.
launcher=/usr/sbin/ambari-server
if grep -Fxq 'HASH="${buildNumber}"' "$launcher"; then
    grep -Fxq 'VERSION="3.0.0.0-0"' "$launcher" || {
        echo 'Unresolved buildNumber in an unexpected Ambari version; refusing repair.' >&2
        exit 1
    }
    if [[ ! -e "$launcher.before-buildnumber-fix" ]]; then
        cp -p "$launcher" "$launcher.before-buildnumber-fix"
    fi
    sed -i 's/^HASH="${buildNumber}"$/HASH="source-archive-3.0.0"/' "$launcher"
    echo 'Repaired Ambari source-archive build identifier in installed launcher.'
fi
env -u buildNumber -u ambariFullVersion bash "$launcher" --version
env -u buildNumber -u ambariFullVersion bash "$launcher" --hash

# This stage deliberately performs no database creation or schema import.
wget https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.28/mysql-connector-java-8.0.28.jar \
    -O /usr/share/java/mysql-connector-java.jar

ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

properties=/etc/ambari-server/conf/ambari.properties
jdbc_url='server.jdbc.url=jdbc:mysql://localhost:3306/ambari?useSSL=true&verifyServerCertificate=false&enabledTLSProtocols=TLSv1.2'
if grep -q '^server.jdbc.url=' "$properties"; then
    sed -i '/^server.jdbc.url=/d' "$properties"
fi
printf '%s\n' "$jdbc_url" >> "$properties"

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
