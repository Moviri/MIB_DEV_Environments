#!/bin/bash
# Run from any directory. Compilation happens only in the builder container.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash build-packages.sh preflight|ambari|bigtop|repo [bigtop-component ...]

  preflight  Check Docker, architecture and build disk space; make no images.
  ambari     Build Ambari 3.0.0 server and agent RPMs.
  bigtop     Build selected Bigtop 3.3.0 components and build dependencies.
             Default: bigtop-select, hadoop, zookeeper (HDFS/YARN/MapReduce).
  repo       Check the built RPMs and write the local-install checksum manifest.
             Pass the same component list used for 'bigtop'.

Environment:
  AMBARI_BUILD_WORK       Source/cache/log directory (default: .package-build).
  AMBARI_BUILD_OUTPUT     RPM repository (default: ambari-repo).
  AMBARI_BUILD_JOBS       Maven build threads (default: 2).
  AMBARI_BUILD_MIN_GB     Minimum free space in work/output filesystem.
                         Defaults: ambari 20 GB, repo 1 GB, other stages 60 GB.

The work filesystem and Docker storage both need room. Recommended starting
capacity: 100 GB free for the core stack; more for additional services.
Builds still download upstream source and Maven/npm dependencies.
Ambari Metrics is not included: see build/README.md for its compatibility issue.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    preflight|ambari|bigtop|repo) stage=$1; shift ;;
    *) usage >&2; exit 2 ;;
esac
if [[ "$stage" != bigtop && "$stage" != repo && $# -ne 0 ]]; then
    echo "Component arguments apply only to bigtop and repo." >&2
    exit 2
fi
components=("$@")
if [[ ${#components[@]} -eq 0 ]]; then
    components=(bigtop-select hadoop zookeeper)
fi
for component in "${components[@]}"; do
    case "$component" in
        bigtop-select|bigtop-utils|bigtop-groovy|bigtop-jsvc|hadoop|zookeeper|hbase|hive|tez|spark|kafka|flink|livy|phoenix|ranger|solr|alluxio|zeppelin) ;;
        *) echo "Unsupported Bigtop component: $component" >&2; exit 2 ;;
    esac
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work=${AMBARI_BUILD_WORK:-$script_dir/.package-build}
output=${AMBARI_BUILD_OUTPUT:-$script_dir/ambari-repo}
jobs=${AMBARI_BUILD_JOBS:-2}
case "$stage" in ambari) default_min_gb=20;; repo) default_min_gb=1;; *) default_min_gb=60;; esac
min_gb=${AMBARI_BUILD_MIN_GB:-$default_min_gb}
for value in "$jobs" "$min_gb"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "Jobs and minimum GB must be positive integers." >&2; exit 2; }
done
[[ $(uname -m) == x86_64 ]] || { echo "Use an x86_64 build host for these containers." >&2; exit 1; }
command -v docker >/dev/null
docker info >/dev/null
mkdir -p "$work" "$output"
work=$(cd "$work" && pwd)
output=$(cd "$output" && pwd)
[[ "$work" != "$output" ]] || { echo "Work and output directories must differ." >&2; exit 2; }
for directory in "$work" "$output"; do
    available_kb=$(df -Pk "$directory" | awk 'NR == 2 {print $4}')
    if (( available_kb < min_gb * 1024 * 1024 )); then
        echo "Insufficient space at $directory: $(( available_kb / 1024 / 1024 )) GB available, $min_gb GB required." >&2
        echo "Choose a larger filesystem with AMBARI_BUILD_WORK and AMBARI_BUILD_OUTPUT." >&2
        exit 1
    fi
done
echo "Work: $work"
echo "RPMs: $output"
echo "Docker storage: $(docker info --format '{{.DockerRootDir}}') (check free space separately)"
[[ "$stage" != preflight ]] || exit 0

mkdir -p "$work/logs" "$work/cache/m2" "$work/cache/gradle" "$work/cache/npm"
# Prevent simultaneous builds from modifying the shared source/output trees.
exec 9>"$work/build.lock"
flock -n 9 || { echo "Another build is using $work." >&2; exit 1; }
log="$work/logs/$(date -u +%Y%m%dT%H%M%SZ)-$stage.log"
exec > >(tee -a "$log") 2>&1
echo "Build log: $log"
image=ambari-rocky8-builder:3.0.0-bigtop3.3.0
docker build --platform linux/amd64 -t "$image" "$script_dir/build"
docker image inspect "$image" --format '{{.Id}}' > "$work/builder-image-id.txt"
cp "$script_dir/build/sources.sha512" "$work/sources.sha512"
docker run --rm --platform linux/amd64 \
    -e BUILD_JOBS="$jobs" \
    -v "$work:/work:Z" -v "$output:/repo:Z" \
    -v "$work/cache/m2:/root/.m2:Z" \
    -v "$work/cache/gradle:/root/.gradle:Z" \
    -v "$work/cache/npm:/root/.npm:Z" \
    "$image" "$stage" "${components[@]}"
