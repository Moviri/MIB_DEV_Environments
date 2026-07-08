#!/usr/bin/env bash
set -euo pipefail

ELASTIC_URL="${ELASTIC_URL:-https://localhost:9200}"
ELASTIC_USER="${ELASTIC_USER:-elastic}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-password}"

curl_args=(
  --fail
  --silent
  --show-error
  --insecure
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}"
  --header "Content-Type: application/x-ndjson"
)

timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
metricbeat_index="metricbeat-dev-$(date -u +%Y.%m.%d)"
filebeat_index="filebeat-dev-$(date -u +%Y.%m.%d)"

curl "${curl_args[@]}" "${ELASTIC_URL}/_bulk" --data-binary @- <<EOF
{"index":{"_index":"${metricbeat_index}"}}
{"@timestamp":"${timestamp}","host":{"name":"dev-linux-01","os":{"platform":"ubuntu","type":"linux"}},"system":{"cpu":{"total":{"pct":0.17}},"memory":{"used":{"pct":0.42}},"network":{"in":{"bytes":524288}}}}
{"index":{"_index":"${metricbeat_index}"}}
{"@timestamp":"${timestamp}","host":{"name":"dev-windows-01","os":{"platform":"windows","type":"windows"}},"system":{"cpu":{"total":{"pct":0.23}},"memory":{"used":{"pct":0.58}},"network":{"in":{"bytes":1048576}}}}
{"index":{"_index":"${filebeat_index}"}}
{"@timestamp":"${timestamp}","host":{"name":"dev-linux-01","os":{"platform":"ubuntu","type":"linux"}},"event":{"module":"apache"},"message":"apache service restart completed"}
{"index":{"_index":"${filebeat_index}"}}
{"@timestamp":"${timestamp}","host":{"name":"dev-windows-01","os":{"platform":"windows","type":"windows"}},"event":{"module":"system"},"message":"windows service restart completed"}
EOF

curl --fail --silent --show-error --insecure --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  "${ELASTIC_URL}/_cat/indices/metricbeat-dev-*,filebeat-dev-*?v"
