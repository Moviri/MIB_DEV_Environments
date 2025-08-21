#!/usr/bin/env bash
# Fix Ambari Metrics Collector (AMS) classpath so it consistently uses Jersey 1.x (JSR-311 1.1)
# and avoids JAX-RS 2.x / jakarta conflicts that cause AbstractMethodError on UriBuilder.
#
# Usage: sudo bash fix-ams-classpath.sh [--debug]
#   --debug : also enable -verbose:class on the collector and set xtrace for this script
#
# This script is idempotent and backs up moved jars into /root/ams-jar-backup.<epoch>.
# It stops AMS, removes conflicting jars from known locations, pins jsr311-api-1.1.1.jar first
# in the classpath, sets HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP, then starts AMS and verifies it.

set -Eeuo pipefail

[[ ${1:-} == "--debug" ]] && { set -x; DEBUG=1; } || DEBUG=0

JAR_URL_JSR311="https://repo1.maven.org/maven2/javax/ws/rs/jsr311-api/1.1.1/jsr311-api-1.1.1.jar"
COLLECTOR_DIR="/usr/lib/ambari-metrics-collector"
HBASE_LIB="/usr/lib/ams-hbase/lib"
BIGTOP_HBASE_LIB="/usr/bigtop/3.3.0/usr/lib/hbase/lib"
AMS_ENV="/etc/ambari-metrics-collector/conf/ams-env.sh"
HBASE_ENV="/usr/lib/ams-hbase/conf/hbase-env.sh"
BACKUP_DIR="/root/ams-jar-backup.$(date +%s)"
LOG_DIR="/var/log/ambari-metrics-collector"
LOG_FILE="$LOG_DIR/fix-ams-classpath.$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*"; }
die()  { echo -e "[ERROR] $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }

stop_ams() {
  info "Stopping Ambari Metrics Collector (if running)"
  /usr/sbin/ambari-metrics-collector stop || true
  sleep 2
  if ss -lntp '( sport = :6188 )' 2>/dev/null | grep -q ':6188'; then
    warn "Port 6188 still listening; attempting graceful shutdown of java process"
    local pid
    pid=$(ss -lntp '( sport = :6188 )' 2>/dev/null | awk '/java/ {match($0,/pid=([0-9]+)/,m); print m[1]}')
    if [[ -n "${pid:-}" ]]; then
      kill "$pid" || true
      sleep 3
      if ss -lntp '( sport = :6188 )' 2>/dev/null | grep -q ':6188'; then
        warn "Process still up; sending SIGKILL"
        kill -9 "$pid" || true
      fi
    fi
  fi
  if ss -lntp '( sport = :6188 )' 2>/dev/null | grep -q ':6188'; then
    die "Failed to free port 6188; aborting to avoid corrupt state"
  fi
}

move_conflicts_from_dir() {
  local d="$1"
  [[ -d "$d" ]] || return 0
  shopt -s nullglob
  local moved=0
  for pattern in 'jakarta.ws.rs-api-*.jar' 'javax.ws.rs-api-2*.jar' 'hadoop-yarn-server-timelineservice-*.jar'; do
    for f in "$d"/$pattern; do
      [[ -f "$f" ]] || continue
      mkdir -p "$BACKUP_DIR"
      info "Backing up conflicting jar $f -> $BACKUP_DIR/"
      mv -v "$f" "$BACKUP_DIR/"
      moved=1
    done
  done
  shopt -u nullglob
  return 0
}

move_conflicts() {
  info "Removing JAX-RS 2.x / jakarta and YARN Timeline v2 jars from known locations"
  move_conflicts_from_dir "$COLLECTOR_DIR"
  move_conflicts_from_dir "$HBASE_LIB"
  move_conflicts_from_dir "$BIGTOP_HBASE_LIB"
  [[ -d "$BACKUP_DIR" ]] && info "Backed up jars are in $BACKUP_DIR" || info "No conflicting jars found to move"
}

ensure_jsr311() {
  mkdir -p "$COLLECTOR_DIR"
  local target="$COLLECTOR_DIR/jsr311-api-1.1.1.jar"
  if [[ ! -f "$target" ]]; then
    info "Fetching jsr311-api-1.1.1.jar into $COLLECTOR_DIR"
    curl -fsSL -o "$target" "$JAR_URL_JSR311" || die "Failed to download $JAR_URL_JSR311"
  else
    info "Found $target"
  fi
  ln -sfn "jsr311-api-1.1.1.jar" "$COLLECTOR_DIR/00-jsr311-api-1.1.1.jar"
  if [[ -d "$HBASE_LIB" ]]; then
    cp -f "$target" "$HBASE_LIB/"
    ln -sfn "jsr311-api-1.1.1.jar" "$HBASE_LIB/00-jsr311-api-1.1.1.jar"
  fi
  if [[ -d "$BIGTOP_HBASE_LIB" ]]; then
    cp -f "$target" "$BIGTOP_HBASE_LIB/"
    ln -sfn "jsr311-api-1.1.1.jar" "$BIGTOP_HBASE_LIB/00-jsr311-api-1.1.1.jar"
  fi
}

pin_env() {
  if [[ -f "$HBASE_ENV" ]]; then
    if ! grep -q 'HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP' "$HBASE_ENV"; then
      info "Adding HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=true to $HBASE_ENV"
      echo 'export HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP=true' >> "$HBASE_ENV"
    else
      info "HBASE_DISABLE_HADOOP_CLASSPATH_LOOKUP already set in $HBASE_ENV"
    fi
  fi
  if [[ $DEBUG -eq 1 ]]; then
    if [[ -f "$AMS_ENV" ]] && ! grep -q -- '-verbose:class' "$AMS_ENV" 2>/dev/null; then
      info "Enabling -verbose:class in $AMS_ENV"
      echo 'export AMS_COLLECTOR_OPTS="$AMS_COLLECTOR_OPTS -verbose:class"' >> "$AMS_ENV"
    fi
  fi
}

start_ams() {
  info "Starting Ambari Metrics Collector"
  /usr/sbin/ambari-metrics-collector start || die "Failed to start AMS"
  # small grace period before verify
  sleep 3
}

verify() {
  local url="http://localhost:6188/ws/v1/timeline/metrics"
  info "Verifying collector endpoint at $url"
  local status
  for i in {1..30}; do
    status=$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)
    if [[ "$status" == "200" || "$status" == "204" ]]; then
      info "Collector responded with HTTP $status (OK)"
      return 0
    elif [[ "$status" == "500" ]]; then
      if grep -q 'AbstractMethodError: javax.ws.rs.core.UriBuilder' "$LOG_DIR/ambari-metrics-collector.log" 2>/dev/null; then
        die "Collector still hitting AbstractMethodError on UriBuilder (JAX-RS mismatch)"
      fi
    fi
    sleep 1
  done
  warn "Timeout waiting for healthy response; last HTTP status: ${status:-none}"
  return 1
}

report() {
  info "=== Post-fix classpath sanity (UriBuilder providers) ==="
  for d in "$COLLECTOR_DIR" "$HBASE_LIB" "$BIGTOP_HBASE_LIB"; do
    [[ -d "$d" ]] || continue
    shopt -s nullglob
    for j in "$d"/*.jar; do
      jar tf "$j" 2>/dev/null | grep -q '^javax/ws/rs/core/UriBuilder.class$' && echo "  - $(basename "$j") in $d"
    done
    shopt -u nullglob
  done
  info "Java runtime: $(java -version 2>&1 | head -n1)"
  info "Listening sockets on 6188:"
  ss -lntp '( sport = :6188 )' 2>/dev/null || true
  info "Logs: $LOG_FILE and $LOG_DIR/ambari-metrics-collector.log"
}

main() {
  [[ $EUID -eq 0 ]] || die "Please run as root"
  need_cmd curl
  need_cmd ss
  need_cmd jar
  stop_ams
  move_conflicts
  ensure_jsr311
  pin_env
  start_ams
  verify || true
  report
  info "Done. If problems persist, share $LOG_FILE."
}

main "$@"
