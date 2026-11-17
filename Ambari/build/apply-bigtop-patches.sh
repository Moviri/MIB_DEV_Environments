#!/bin/bash
set -euo pipefail

bigtop_dir=${1:?Usage: apply-bigtop-patches.sh BIGTOP_SOURCE_DIRECTORY}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
patch_name=patch9999-ambari-catalog-node12.diff
source_patch="$script_dir/patches/$patch_name"
destination="$bigtop_dir/bigtop-packages/src/common/hadoop/$patch_name"

[[ -f "$source_patch" && -d "$(dirname "$destination")" ]] || {
    echo 'Missing Catalog compatibility patch or Bigtop Hadoop packaging directory.' >&2
    exit 1
}
if ! cmp -s "$source_patch" "$destination"; then
    # packages.gradle copies patch*.diff into the Hadoop SRPM and applies them
    # during rpmbuild. Invalidate markers BEFORE installing a new patch so an
    # interrupted update cannot leave a stale SRPM marked as complete.
    rm -f "$bigtop_dir/build/hadoop/.srpm" "$bigtop_dir/build/hadoop/.rpm"
    cp "$source_patch" "$destination"
    echo 'Installed Catalog Node 12 compatibility patch; Hadoop packaging will rebuild.'
fi
