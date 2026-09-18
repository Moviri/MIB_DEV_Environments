# Deploy to another Docker host

The repository's `AppDynamics/` directory is self-contained. Use the same Compose project on a supported Docker host running Linux containers. Run the commands below from that directory unless shown otherwise, and substitute your own hostnames, paths, and host IDs. Shell commands are labeled where platform-specific syntax is needed; see the [README](../README.md#start-locally) for Windows and Linux quick starts.

## Deploy

1. Clone the development environments repository into an approved directory on the host:

   ```bash
   git clone https://github.com/Moviri/MIB_DEV_Environments.git
   cd MIB_DEV_Environments/AppDynamics
   ```

   Alternatively, transfer the source-only archive created on Windows by `scripts/package.ps1`. It excludes `.env`, agent payloads, build outputs, and downloaded ZIPs:

   ```powershell
   .\scripts\package.ps1
   # Transfer artifacts/capital-lab-source.zip through your normal file-transfer workflow.
   ```

   Extract the archive on the destination host and enter its directory. For example, in a Unix shell:

   ```bash
   unzip capital-lab-source.zip -d capital-lab
   cd capital-lab
   ```

2. Install Docker with Compose and enable Linux containers. Ensure outbound HTTPS to Maven Central, image registries and the AppDynamics Controller is available. The Controller does not need an inbound connection to the demo.
3. Prepare private configuration, preserving any existing `.env`:

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

   In PowerShell, use `Copy-Item .env.example .env` and restrict file access using the host's permissions.

4. Transfer the configured Java Agent ZIP privately, and import it using Python 3.10+:

   ```bash
   python3 scripts/configure-agent.py /path/to/AppServerAgent.zip --host-id capital-lab-host-02
   ```

   Use `python` instead of `python3` if that is your Python executable. Alternatively extract the distribution into `agents/java`, then fill the Controller hostname/account/access key, enable the agent in `.env`, and set `APPDYNAMICS_AGENT_UNIQUE_HOST_ID=capital-lab-host-02`. Preserve `Capital-Lab` as the application name to share an application with another deployment, or choose a different application name to test separate applications. Use a distinct host ID for every Docker host. Restrict access to the directory containing the agent's configuration; its account key is sensitive. The container runs as UID 10001 and needs read access to the distribution.

5. Before the first start, choose a database password in `.env`. Then:

   ```bash
   docker compose build portal
   docker compose up -d --wait
   docker compose --profile test run --rm smoke
   docker compose --profile load up -d loadgen
   ```

For an offline lab, build/save the application, PostgreSQL and Python images on a machine with the same CPU architecture and transfer them with `docker save` / `docker load`, or use your internal registry. Do not bake the agent account key into an image. Rebuild on the destination for ARM64 unless you have explicitly prepared matching images and agent binaries.

## Browser access

The portal remains bound to `127.0.0.1:8088` on the Docker host. If the host supports SSH, forward it to an unused port on your workstation:

```sh
ssh -L 18088:127.0.0.1:8088 user@your-docker-host
```

Then open `http://localhost:18088`. This also provides a secure browser context for UUID generation. You do not need to expose PostgreSQL or the internal services. For shared browser access, put an authenticated HTTPS proxy in front of the portal using your established access controls.

## Host metrics for the Moviri ETL

Run one AppDynamics **Machine Agent directly on the Linux host running Docker Engine** to collect that host's CPU, memory, disk and network metrics. If Docker Engine runs inside a Linux VM, run these steps inside that existing VM; the measurements describe the VM's resources. The three Java agents remain in their application containers.

The ETL can discover a compute host from Java-agent node metadata even when there are no hardware samples. All three demo JVMs share one host ID, so the same compute host can appear under each tier. One Machine Agent with that matching ID supplies the hardware data for those nodes; see the [installation scenarios](https://help.splunk.com/en/appdynamics-saas/infrastructure-visibility/26.8.0/machine-agent/install-the-machine-agent/machine-agent-installation-scenarios).

### Install and start on the Linux Docker host

Run the following commands from the repository's `AppDynamics/` directory **in a shell on the Linux Docker host**. Use its existing `.env`, already configured for the Java agents.

1. Confirm the host ID used by the running application:

   ```bash
   docker compose exec -T portal printenv APPDYNAMICS_AGENT_UNIQUE_HOST_ID
   ```

   It should match `APPDYNAMICS_AGENT_UNIQUE_HOST_ID` in `.env` and in the other two Java services. Keep this ID when adding the Machine Agent to an existing deployment. Give separate Docker hosts separate IDs.

2. Download the **Linux Machine Agent ZIP with bundled JRE** for the host's CPU architecture from AppDynamics Downloads. This is a separate distribution from the Java Agent ZIP. Follow the current [Linux ZIP installation instructions](https://help.splunk.com/en/appdynamics-saas/infrastructure-visibility/26.5.0/machine-agent/install-the-machine-agent/linux-install-using-zip-with-bundled-jre) and [supported environments](https://help.splunk.com/en/appdynamics-saas/infrastructure-visibility/26.8.0/machine-agent/machine-agent-requirements-and-supported-environments).

   For a new installation, extract it into the empty agent directory, substituting the downloaded filename:

   ```bash
   mkdir -p agents/machine
   unzip /path/to/MachineAgent.zip -d agents/machine
   test -f agents/machine/machineagent.jar
   test -x agents/machine/bin/machine-agent
   ```

   The account running the agent needs read/write access to this directory. The bundled launcher uses its included JRE; Java installed inside an application container is not a host Java installation. If a Machine Agent is already running on this host, configure that installation instead of starting a second one.

3. In `agents/machine/conf/controller-info.xml`, leave `application-name`, `tier-name`, and `node-name` empty. Clear any values prefilled by a download wizard. This host-level agent will associate with existing application nodes using their shared host ID.

4. Start it in the foreground using the Controller connection settings from `.env`:

   ```bash
   (
       # Source only your own trusted, shell-compatible .env file.
       # Sourcing it executes shell syntax; the configure-agent.py output is compatible.
       set -a
       . ./.env
       set +a
       unset APPDYNAMICS_AGENT_APPLICATION_NAME APPDYNAMICS_AGENT_TIER_NAME APPDYNAMICS_AGENT_NODE_NAME
       export APPDYNAMICS_SIM_ENABLED=false
       export APPDYNAMICS_DOCKER_ENABLED=false
       agents/machine/bin/machine-agent \
           -D appdynamics.agent.uniqueHostId="$APPDYNAMICS_AGENT_UNIQUE_HOST_ID" \
           -D appdynamics.force.default.ssl.certificate.validation=true
   )
   ```

The environment supplies the Controller hostname, port, TLS setting, account name, access key and shared host ID. The subshell keeps these settings local to this launch. `APPDYNAMICS_SIM_ENABLED=false` selects basic machine monitoring; enable Server Visibility or Docker Visibility separately only when needed and licensed. Review startup and connection messages in `agents/machine/logs/machine-agent.log`. Stop this foreground agent with Ctrl+C.

For unattended operation, use the agent's supported Linux service installation or your host's service manager after verifying collection. Its service configuration must retain the same Controller/account settings, host ID and monitoring flags, with application/tier/node unset. A service does not inherit variables from this interactive shell. Keep the access key in a protected configuration file and run only one instance.

### Verify collection before rerunning the ETL

Allow several reporting intervals, then open **Capital-Lab** in the Controller Metric Browser. Under **Application Infrastructure Performance → a tier → Individual Nodes → its node → Hardware Resources**, check for timestamped CPU and memory samples. For example, the connector requests paths such as:

```text
Application Infrastructure Performance|Portal|Individual Nodes|<portal-node>|Hardware Resources|CPU|%Busy
Application Infrastructure Performance|Portal|Individual Nodes|<portal-node>|Hardware Resources|Memory|Used %
```

Confirm hardware samples on the other two tiers' nodes as well. Then run the ETL for an interval containing samples collected **after** the Machine Agent started; older intervals remain empty. Basic monitoring is verified through the application's Hardware Resources paths. The separate Servers view and additional Server Visibility metrics depend on their configuration and entitlement.

If the paths remain empty, check the Machine Agent log for connection, authentication or licensing errors, compare its host ID with the running Java agents, and confirm application/tier/node were left unset in both its environment and XML. If the Controller contains samples but the ETL does not, check the extraction interval, filters and API access against those same paths.

These are Linux **host** measurements, not per-container quotas or utilization. An isolated Machine Agent container can see different resource namespaces; use AppDynamics' [Docker Visibility setup](https://help.splunk.com/en/appdynamics-on-premises/infrastructure-visibility/26.4.0/monitor-containers-with-docker-visibility) when per-container measurements are required. Separate Database Agent/collector setup is needed for PostgreSQL server metrics; Java JDBC timing does not replace it.

## Migration checks

- Three healthy Java services and PostgreSQL; portal reachable through SSH.
- The expected application, tiers, and destination node identities in AppDynamics.
- Distinct source and destination host IDs if both stacks run simultaneously.
- Calls, response times, errors and JVM values during the selected ETL extraction interval.
- Host hardware values only after the Machine Agent is connected and mapped.
- Existing ETL API authentication, application filters and sample interval set for the trial.

After moving the workload, stop the source host's load generator if you want only destination traffic in the same application. Controller history remains available according to the Controller's retention policy.
