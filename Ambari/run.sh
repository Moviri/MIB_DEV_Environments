#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --fresh)
        # Refuse an existing project, including stopped containers. The server
        # installer imports a schema and is meant for a new database.
        existing=$(docker compose ps --all --quiet)
        if [[ -n "$existing" ]]; then
            echo 'This Compose project already has containers. Run --fresh on a clean host.' >&2
            exit 1
        fi
        if [[ ! -s ambari-repo/LOCAL_RPMS.sha256 || ! -s ambari-repo/RPM-INVENTORY.tsv ]]; then
            echo 'Build the complete bundle with bash build-packages.sh all or copy a finalized ambari-repo/ here.' >&2
            exit 1
        fi
        for package in ambari-metrics-{collector,monitor,hadoop-sink,grafana}; do
            if ! grep -Fxq "$(printf '%s\t3.1.0\t2\tx86_64' "$package")" ambari-repo/RPM-INVENTORY.tsv; then
                echo "Missing $package release 3.1.0-2. Run the metrics and repo build stages." >&2
                exit 1
            fi
        done
        for package in ambari-{server,agent} bigtop-select hadoop_3_3_0 zookeeper_3_3_0 hbase_3_3_0 ranger_3_3_0-{hdfs,yarn}-plugin; do
            if ! grep -q "^${package}"$'\t' ambari-repo/RPM-INVENTORY.tsv; then
                echo "Missing $package in the finalized bundle. Run the default build stages." >&2
                exit 1
            fi
        done
        (cd ambari-repo && sha256sum --quiet --strict --check LOCAL_RPMS.sha256)
        docker compose up -d
        ;;
    '') ;; # Original entry point for already-created containers.
    *) echo "Usage: $0 [--fresh]" >&2; exit 2 ;;
esac

cd scripts
for script in setup-ambari-repo.sh setup.sh install-ambari-server.sh install-ambari-agent.sh; do
    echo "Running $script"
    bash "$script"
done
if [[ ${1:-} == --fresh ]]; then
    bash verify-metrics-repo.sh ambari
fi
