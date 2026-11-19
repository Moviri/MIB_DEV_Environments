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
install_patch hadoop patch9999-ambari-glassfish-el.diff
install_patch ranger patch9999-ambari-kylin-linq4j.diff
install_patch ranger patch9999-ambari-ranger-distro-assembly.diff

# install already runs compile and package. Requesting package separately
# makes Maven attach the same distribution artifacts a second time.
driver="$bigtop_dir/bigtop-packages/src/common/ranger/do-component-build"
if grep -Fxq 'mvn clean compile package install \' "$driver"; then
    rm -f "$bigtop_dir/build/ranger/.srpm" "$bigtop_dir/build/ranger/.rpm"
    sed -i 's/^mvn clean compile package install /mvn clean install /' "$driver"
fi
grep -Fxq 'mvn clean install \' "$driver" || {
    echo "Unexpected Maven command in Ranger's do-component-build" >&2
    exit 1
}
