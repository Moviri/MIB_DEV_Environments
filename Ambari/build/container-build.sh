#!/bin/bash
set -eo pipefail
# The upstream toolchain profile may reference unset optional variables.
source /etc/profile.d/bigtop.sh
set -u
stage=${1:?Missing stage}
shift
components=("$@")
mkdir -p /work/downloads /work/sources

fetch_source() {
    local name=$1 url=$2 destination=$3 expected actual
    expected=$(awk -v name="$name" '$2 == name {print $1}' /work/sources.sha512)
    [[ ${#expected} -eq 128 ]] || { echo "Missing pinned checksum for $name" >&2; exit 1; }
    if [[ ! -f "/work/downloads/$name" ]]; then
        # Keep partial downloads for a retry. Never extract unchecked content.
        curl --fail --location --retry 5 --connect-timeout 30 \
            --continue-at - --output "/work/downloads/$name.part" "$url"
        actual=$(sha512sum "/work/downloads/$name.part" | awk '{print $1}')
        [[ "$actual" == "$expected" ]] || { echo "Checksum mismatch: $name.part" >&2; exit 1; }
        mv "/work/downloads/$name.part" "/work/downloads/$name"
    fi
    actual=$(sha512sum "/work/downloads/$name" | awk '{print $1}')
    [[ "$actual" == "$expected" ]] || { echo "Checksum mismatch: $name" >&2; exit 1; }
    if [[ ! -d "$destination" ]]; then
        mkdir -p "$destination.extracting"
        tar -xzf "/work/downloads/$name" --strip-components=1 -C "$destination.extracting"
        mv "$destination.extracting" "$destination"
    fi
}

copy_rpms() {
    local source=$1 group=$2 file arch count=0
    mkdir -p "/repo/$group"
    while IFS= read -r -d '' file; do
        arch=$(rpm -qp --qf '%{ARCH}' "$file")
        case "$arch" in x86_64|noarch) ;; *) echo "Unexpected architecture: $file ($arch)" >&2; exit 1;; esac
        cp "$file" "/repo/$group/"
        count=$((count + 1))
    done < <(find "$source" -type f -name '*.rpm' ! -name '*.src.rpm' -print0)
    (( count > 0 )) || { echo "No binary RPMs found in $source" >&2; exit 1; }
}

case "$stage" in
    ambari)
        # Invalidate any previously finalized bundle before changing its RPMs.
        rm -f /repo/LOCAL_RPMS.sha256
        fetch_source apache-ambari-3.0.0-src.tar.gz \
            https://archive.apache.org/dist/ambari/ambari-3.0.0/apache-ambari-3.0.0-src.tar.gz \
            /work/sources/ambari-3.0.0
        export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
        export PATH="$JAVA_HOME/bin:$PATH"
        cd /work/sources/ambari-3.0.0
        mvn --batch-mode -T "${BUILD_JOBS:-2}" clean install package rpm:rpm \
            -Drevision=3.0.0.0.0 -DskipTests -Dmaven.test.skip=true \
            -DskipPythonTests -Drat.skip=true -Dfindbugs.skip=true -Dcheckstyle.skip=true
        copy_rpms ambari-server/target/rpm/ambari-server/RPMS ambari
        copy_rpms ambari-agent/target/rpm/ambari-agent/RPMS ambari
        ;;
    bigtop)
        rm -f /repo/LOCAL_RPMS.sha256
        fetch_source bigtop-3.3.0-project.tar.gz \
            https://archive.apache.org/dist/bigtop/bigtop-3.3.0/bigtop-3.3.0-project.tar.gz \
            /work/sources/bigtop-3.3.0
        export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
        export PATH="$JAVA_HOME/bin:$PATH"
        cd /work/sources/bigtop-3.3.0
        targets=()
        for component in "${components[@]}"; do targets+=("$component-pkg"); done
        # Bigtop's dependency graph omits bigtop-select; always build it explicitly.
        ./gradlew --no-daemon -Dbuildwithdeps=true \
            -PparentDir=/usr/bigtop -PpkgSuffix -PbuildThreads="${BUILD_JOBS:-2}" \
            bigtop-select-pkg "${targets[@]}"
        copy_rpms output bigtop
        ;;
    repo)
        rm -f /repo/LOCAL_RPMS.sha256
        cd /repo
        inventory=$(mktemp)
        trap 'rm -f "$inventory"' EXIT
        while IFS= read -r -d '' file; do
            rpm -qp --qf '%{NAME}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\n' "$file" >> "$inventory"
        done < <(find ambari bigtop -type f -name '*.rpm' ! -name '*.src.rpm' -print0)
        require_package() {
            local name=$1
            awk -F '\t' -v name="$name" '$1 == name {found=1} END {exit !found}' "$inventory" || {
                echo "Missing required RPM: $name. Build the matching stage first." >&2; exit 1;
            }
        }
        require_package ambari-server
        require_package ambari-agent
        require_package bigtop-select
        for component in "${components[@]}"; do
            case "$component" in
                bigtop-*) require_package "$component" ;;
                ranger) require_package ranger_3_3_0-admin ;;
                *) require_package "${component}_3_3_0" ;;
            esac
        done
        # A package inventory is a packaging check, not a cluster smoke test.
        sort "$inventory" > RPM-INVENTORY.tsv
        cp /work/sources.sha512 SOURCE-SHA512SUMS
        cp /work/builder-image-id.txt BUILDER-IMAGE.txt
        printf '%s\n' "${components[@]}" > BIGTOP-COMPONENTS.txt
        createrepo_c .
        find ambari bigtop -type f -name '*.rpm' ! -name '*.src.rpm' -print0 \
            | sort -z | xargs -0 -r sha256sum > LOCAL_RPMS.sha256.tmp
        [[ -s LOCAL_RPMS.sha256.tmp ]] || { echo "Empty RPM repository" >&2; exit 1; }
        mv LOCAL_RPMS.sha256.tmp LOCAL_RPMS.sha256
        echo 'Local package bundle finalized. Fresh-cluster installation remains to be tested.'
        ;;
    *) echo "Unknown build stage: $stage" >&2; exit 2 ;;
esac
