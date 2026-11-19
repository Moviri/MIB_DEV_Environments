#!/usr/bin/env bash
# Verify the stack repository on the four nodes used by this Compose cluster.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${1:-BIGTOP-3.3.0-repo-1}
packages=(ambari-metrics-{monitor,collector,hadoop-sink,grafana})

for host in bigtop-hostname{0..3}; do
    echo "Checking $host ($repo)"
    available=$(docker compose exec -T "$host" dnf -q --refresh --disablerepo='*' \
        --enablerepo="$repo" --setopt="$repo.skip_if_unavailable=False" \
        repoquery --available --qf '%{name}' "${packages[@]}")
    for package in "${packages[@]}"; do
        if ! grep -Fxq "$package" <<< "$available"; then
            echo "$host cannot resolve $package from $repo" >&2
            exit 1
        fi
    done
done
echo 'All four nodes can resolve all four Ambari Metrics RPMs.'
