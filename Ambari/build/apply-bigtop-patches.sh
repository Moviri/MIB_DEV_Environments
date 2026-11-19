#!/bin/bash
set -euo pipefail

bigtop_dir=${1:?Usage: apply-bigtop-patches.sh BIGTOP_SOURCE_DIRECTORY}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install_patch() {
    local component=$1 patch_name=$2
    local source_patch="$script_dir/patches/$patch_name"
    local destination="$bigtop_dir/bigtop-packages/src/common/$component/$patch_name"

    if ! cmp -s "$source_patch" "$destination"; then
        # Invalidate completion markers before installing a changed SRPM input.
        rm -f "$bigtop_dir/build/$component/.srpm" "$bigtop_dir/build/$component/.rpm"
        cp "$source_patch" "$destination"
        echo "Installed $patch_name; $component packaging will rebuild."
    fi
}

install_patch hadoop patch9999-ambari-catalog-node12.diff
install_patch ranger patch9999-ambari-kylin-linq4j.diff
