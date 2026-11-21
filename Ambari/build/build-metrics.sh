# Sourced by container-build.sh with its verified archive helpers and build lock.
revision=b1ac7d78d73818ae896bff279ef7d3f27ef76741
source_dir="/work/sources/ambari-metrics-$revision"
fetch_source "ambari-metrics-$revision.tar.gz" \
    "https://codeload.github.com/apache/ambari-metrics/tar.gz/$revision" "$source_dir"

bigtop_url=https://s3.amazonaws.com/repo.bigtop.apache.org/bigtop-stack-binary/3.2.0/centos-7/x86_64
hbase=hbase-2.4.13-bin.tar.gz
hadoop=hadoop-3.3.4.tar.gz
phoenix=phoenix-hbase-2.4-5.1.2-bin.tar.gz
grafana=grafana-11.5.2.linux-amd64.tar.gz
for archive in "$hbase" "$hadoop" "$phoenix"; do
    fetch_archive "$archive" "$bigtop_url/$archive"
done
fetch_archive "$grafana" "https://dl.grafana.com/oss/release/$grafana"

cd "$source_dir"
# rpmbuild can be retried with a cached source tree. Restore the two inputs
# from the verified archive so every attempt applies exactly the same patch.
tar -xzf "/work/downloads/ambari-metrics-$revision.tar.gz" --strip-components=1 \
    "ambari-metrics-$revision/ambari-metrics-timelineservice/conf/unix/ambari-metrics-collector" \
    "ambari-metrics-$revision/ambari-metrics-grafana/conf/unix/ambari-metrics-grafana"
patch --batch --fuzz=0 -p1 < /opt/ambari-build/metrics-launchers.patch
# Grafana produces files read directly by the assembly without a Maven dependency.
mvn --batch-mode clean package -Prpm -Drelease.version=2 -DskipTests -DskipPythonTests=true -Drat.skip=true \
    -Dhbase.tar="file:/work/downloads/$hbase" -Dhadoop.tar="file:/work/downloads/$hadoop" \
    -Dphoenix.tar="file:/work/downloads/$phoenix" -Dgrafana.tar="file:/work/downloads/$grafana"

rpms=()
for suffix in collector monitor hadoop-sink grafana; do
    name="ambari-metrics-$suffix"
    files=(ambari-metrics-assembly/target/rpm/"$name"/RPMS/x86_64/*.rpm)
    [[ ${#files[@]} -eq 1 && -f "${files[0]}" && $(rpm -qp --qf '%{NAME}-%{RELEASE}.%{ARCH}' "${files[0]}") == "$name-2.x86_64" ]] || {
        echo "Expected one x86_64 RPM for $name" >&2; exit 1
    }
    rpms+=("$(realpath "${files[0]}")")
done

# Validate the packaged monitor with Rocky's Python and the same psutil build
# that the installed launcher performs on its first start.
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
cd "$check_dir"
rpm2cpio "${rpms[1]}" | cpio -idm --quiet
cd usr/lib/python3.9/site-packages/resource_monitoring
python3 -m compileall -q main.py core
(cd psutil && python3 setup.py build)
python3 -c 'from core.host_info import HostInfo; import psutil; assert psutil.cpu_times().user >= 0'

# Keep the live bundle valid while building. Publish only after all checks pass.
rm -f /repo/LOCAL_RPMS.sha256
mkdir -p /repo/metrics
cp "${rpms[@]}" /repo/metrics/
cp /work/builder-image-id.txt /repo/metrics/BUILDER-IMAGE.txt
