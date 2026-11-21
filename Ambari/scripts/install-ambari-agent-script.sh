#!/bin/bash

set -ex

### Add by call518
ln -sf /usr/bin/python3 /usr/bin/python
mkdir -p /run/chrony
touch /run/chrony/chronyd.pid
###

tee /etc/yum.repos.d/ambari.repo << EOF
[ambari]
name=Ambari Repository
baseurl=http://bigtop-hostname0
gpgcheck=0
enabled=1
EOF

# ambari agent
yum install -y python3 python3-distro
yum install -y java-17-openjdk-devel
yum install -y java-1.8.0-openjdk-devel
yum install -y ambari-agent
yum install -y chrony

# Recover agents installed from the original source-archive RPMs. The agent
# version omits the package release suffix used by the server launcher.
launcher=/var/lib/ambari-agent/bin/ambari-agent
if grep -Fxq 'HASH="${buildNumber}"' "$launcher"; then
    grep -Fxq 'VERSION="3.0.0.0"' "$launcher" || {
        echo 'Unresolved buildNumber in an unexpected Ambari agent version; refusing repair.' >&2
        exit 1
    }
    if [[ ! -e "$launcher.before-buildnumber-fix" ]]; then
        cp -p "$launcher" "$launcher.before-buildnumber-fix"
    fi
    sed -i 's/^HASH="${buildNumber}"$/HASH="source-archive-3.0.0"/' "$launcher"
fi
env -u buildNumber -u ambariVersion bash "$launcher" --version
env -u buildNumber -u ambariVersion bash "$launcher" --hash

# setup agent
sed -i "s/hostname=.*/hostname=bigtop-hostname0.demo.local/" /etc/ambari-agent/conf/ambari-agent.ini

# The launcher returns 0 for running, 2 for a stale PID, and 3 for stopped.
# Check status in a conditional so expected nonzero codes survive set -e.
if ambari-agent status; then
	ambari-agent restart
else
    status=$?
    case "$status" in
        2|3) ambari-agent start ;;
        *) echo "Ambari agent status failed with exit code $status." >&2; exit "$status" ;;
    esac
fi

# cleanup packages that don't need to be installed
yum remove -y rubygem-multi_json rubygem-semantic_puppet cpp-hocon rubygem-hocon rubygem-puppet-resource_api hiera leatherman ruby-facter rubygem-concurrent-ruby rubygem-deep_merge puppet rubygem-httpclient ruby-augeas facter yaml-cpp

# setup chrony 
systemctl enable chronyd
systemctl start chronyd
