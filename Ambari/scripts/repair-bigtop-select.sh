#!/bin/bash
set -euo pipefail

ambari_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ambari_dir"
for host in bigtop-hostname0 bigtop-hostname1 bigtop-hostname2 bigtop-hostname3; do
    echo "Repairing and checking Bigtop selector on $host"
    docker compose cp build/prepare-bigtop-select.py "$host:/root/prepare-bigtop-select.py"
    docker compose exec -T "$host" python3 /root/prepare-bigtop-select.py \
        /usr/lib/bigtop-select/distro-select --backup
    docker compose exec -T "$host" ambari-python-wrap /usr/lib/bigtop-select/distro-select packages
    docker compose exec -T "$host" ambari-python-wrap /usr/lib/bigtop-select/distro-select versions
done
