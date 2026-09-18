#!/bin/sh
set -eu

export APPDYNAMICS_AGENT_NODE_NAME="${APPDYNAMICS_AGENT_NODE_NAME:-${DEMO_ROLE:-portal}-${HOSTNAME:-local}}"
export APPDYNAMICS_AGENT_BASE_DIR=/tmp/appdynamics

case "${APPDYNAMICS_ENABLED:-false}" in
  true)
    : "${APPDYNAMICS_CONTROLLER_HOST_NAME:?Set the Controller hostname}"
    : "${APPDYNAMICS_AGENT_ACCOUNT_NAME:?Set the Controller account name}"
    : "${APPDYNAMICS_AGENT_ACCOUNT_ACCESS_KEY:?Set the agent account access key}"
    if [ ! -f /opt/appdynamics/javaagent.jar ]; then
      echo 'AppDynamics is enabled but agents/java/javaagent.jar is missing. Extract the complete Java Agent distribution there.' >&2
      exit 1
    fi
    exec java -javaagent:/opt/appdynamics/javaagent.jar \
      -Dappdynamics.force.default.ssl.certificate.validation=true \
      -XX:InitialRAMPercentage=10 -XX:MaxRAMPercentage=55 -jar /app/capital-lab.jar
    ;;
  false)
    exec java -XX:InitialRAMPercentage=10 -XX:MaxRAMPercentage=55 -jar /app/capital-lab.jar
    ;;
  *) echo 'APPDYNAMICS_ENABLED must be true or false' >&2; exit 1 ;;
esac
