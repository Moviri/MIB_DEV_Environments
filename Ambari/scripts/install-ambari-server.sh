#!/bin/bash

set -ex

docker compose cp configure-ambari-server-script.sh bigtop-hostname0:/root/configure-ambari-server-script.sh
docker compose cp install-ambari-server-script.sh bigtop-hostname0:/root/install-ambari-server-script.sh
docker compose exec -T bigtop-hostname0 /bin/bash /root/install-ambari-server-script.sh "$@"

