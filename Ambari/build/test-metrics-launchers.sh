#!/usr/bin/env bash
# Exercise the delivered RPM payloads inside a disposable Rocky 8 container.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
repo=$(cd "${AMBARI_BUILD_OUTPUT:-ambari-repo}" && pwd)
docker run --rm -i --network none --platform linux/amd64 \
    -v "$repo:/rpms:ro,z" --entrypoint bash ambari-metrics-rocky8-builder:b1ac7d78 -se <<'ROCKY'
set -o pipefail
cd /
rpm2cpio /rpms/metrics/ambari-metrics-grafana-3.1.0-2.x86_64.rpm | cpio -idm --quiet
rpm2cpio /rpms/metrics/ambari-metrics-collector-3.1.0-2.x86_64.rpm |
    cpio -idm --quiet './usr/sbin/ambari-metrics-collector' './usr/lib/ambari-metrics-collector/*.jar'

# Exercise UriBuilder with the actual launcher's classpath and Jersey provider.
cd /tmp
cat > UriCheck.java <<'JAVA'
import java.net.URI;
import javax.ws.rs.core.UriBuilder;
public class UriCheck {
    public static void main(String[] args) {
        URI expected = URI.create("http://localhost:6188/ws/v1/timeline/metrics/");
        if (!UriBuilder.fromUri(expected.toString()).build().equals(expected)) {
            throw new AssertionError("Jersey did not construct the Metrics endpoint");
        }
    }
}
JAVA
classpath=$(sed -n 's/.*"-cp" "${COLLECTOR_CONF_DIR}:\([^"]*\):${COLLECTOR_ADDITIONAL_CLASSPATH}".*/\1/p' \
    /usr/sbin/ambari-metrics-collector | sort -u)
javac -cp "$classpath" UriCheck.java
java -Djavax.ws.rs.ext.RuntimeDelegate=com.sun.jersey.server.impl.provider.RuntimeDelegateImpl \
    -cp ".:$classpath" UriCheck
echo 'PASS: collector Jersey URI construction'

useradd --system ams
. /etc/ambari-metrics-grafana/conf/ams-grafana-env.sh
install -d -o ams "$AMS_GRAFANA_DATA_DIR" "$AMS_GRAFANA_LOG_DIR" "$AMS_GRAFANA_PID_DIR"
launcher=/usr/sbin/ambari-metrics-grafana
pidfile=$AMS_GRAFANA_PID_DIR/grafana-server.pid
runuser -u ams -- touch "$pidfile"
runuser -u ams -- "$launcher" start
curl -fsS --retry 10 --retry-delay 1 --retry-connrefused --max-time 3 \
    http://127.0.0.1:3000/api/health | python3 -c 'import json,sys; assert json.load(sys.stdin)["database"] == "ok"'
pid=$(cat "$pidfile")
runuser -u ams -- "$launcher" start
test "$(cat "$pidfile")" = "$pid"
runuser -u ams -- "$launcher" stop
test ! -e "$pidfile"
# A stale PID may since have been allocated to another service.
sleep 60 &
other=$!
echo "$other" > "$pidfile"
runuser -u ams -- "$launcher" stop
kill -0 "$other"
echo 'PASS: Grafana stale PID recovery, healthy database, repeated start and safe stop'
ROCKY
