# Boston Linux Docker host

The repository's `AppDynamics/` directory is self-contained and uses the same Compose project on Windows and Linux. Run the commands below from that directory unless shown otherwise. No Boston hostname or SSH destination is assumed.

## Deploy

1. Clone the development environments repository into an approved directory on the host:

   ```bash
   git clone https://github.com/Moviri/MIB_DEV_Environments.git
   cd MIB_DEV_Environments/AppDynamics
   ```

   Alternatively, transfer the source-only archive created on Windows by `scripts/package.ps1`. It excludes `.env`, agent payloads, build outputs, and downloaded ZIPs:

   ```powershell
   .\scripts\package.ps1
   # Transfer artifacts/capital-lab-source.zip to the lab through your normal SSH workflow.
   ```

   Extract the archive on Linux and enter its directory:

   ```bash
   unzip capital-lab-source.zip -d capital-lab
   cd capital-lab
   ```

2. On the Linux host, install Docker Engine and Compose through your normal lab process. Ensure outbound HTTPS to Maven Central, image registries and the AppDynamics Controller is available. The Controller does not need an inbound connection to this lab.
3. Prepare private configuration, preserving any existing `.env`:

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

4. Transfer the configured Java Agent ZIP privately, and import it using Python 3.10+:

   ```bash
   python3 scripts/configure-agent.py /path/to/AppServerAgent.zip --host-id capital-lab-boston-01
   ```

   Alternatively extract the distribution into `agents/java`, then fill the Controller hostname/account/access key, enable the agent in `.env`, and set `APPDYNAMICS_AGENT_UNIQUE_HOST_ID=capital-lab-boston-01`. Preserve `Capital-Lab` as the application name to share an application with Windows, or choose a different application name to test separate applications. Use a distinct host ID for every Docker host. Restrict access to the directory containing the agent's configuration; its account key is sensitive. The container runs as UID 10001 and needs read access to the distribution.

5. Before the first start, choose a database password in `.env`. Then:

   ```bash
   docker compose build portal
   docker compose up -d --wait
   docker compose --profile test run --rm smoke
   docker compose --profile load up -d loadgen
   ```

For an offline lab, build/save the application, PostgreSQL and Python images on a machine with the same CPU architecture and transfer them with `docker save` / `docker load`, or use your internal registry. Do not bake the agent account key into an image. Rebuild on the destination for ARM64 unless you have explicitly prepared matching images and agent binaries.

## Browser access

The portal remains bound to `127.0.0.1:8088` on the Linux host. Forward it to an unused local port from Windows:

```powershell
ssh -L 18088:127.0.0.1:8088 user@your-boston-docker-host
```

Then open `http://localhost:18088`. This also provides a secure browser context for UUID generation. You do not need to expose PostgreSQL or the internal services. If the lab needs shared browser access, put an authenticated HTTPS proxy in front of the portal using the lab's established access controls.

## Host metrics for the Moviri ETL

Run one AppDynamics **Machine Agent on the Linux host** to obtain real host CPU, memory, disk and network data. Do not use a basic, isolated agent container as evidence of host hardware metrics: it can report its own namespace instead. For container visibility, use AppDynamics' documented Docker Visibility installation and its corresponding permissions/licensing.

Use a supported Linux Machine Agent distribution from the trial/download portal. Configure its Controller settings to match the Java agents, set the **same unique host ID** as the three JVMs on this host (`capital-lab-boston-01`), and leave application, tier, and node name unset for this host-level installation. According to the [installation scenarios](https://help.splunk.com/appdynamics-saas/infrastructure-visibility/25.4.0/machine-agent/install-the-machine-agent/machine-agent-installation-scenarios), matching IDs allow one Machine Agent to report hardware metrics for multiple app-agent nodes.

An example foreground launch from this project directory after extracting a Machine Agent to `agents/machine`:

```bash
# Source only your own trusted .env file. It contains executable shell syntax.
set -a
. ./.env
set +a
unset APPDYNAMICS_AGENT_APPLICATION_NAME APPDYNAMICS_AGENT_TIER_NAME APPDYNAMICS_AGENT_NODE_NAME
export APPDYNAMICS_SIM_ENABLED=false
java -Dappdynamics.agent.uniqueHostId="$APPDYNAMICS_AGENT_UNIQUE_HOST_ID" \
     -jar agents/machine/machineagent.jar
```

Use the agent's bundled Java executable if required by that distribution, and follow its current installation instructions. `APPDYNAMICS_SIM_ENABLED=false` keeps basic machine monitoring; enable Server Visibility only when included in the trial and needed. Persist the agent using your existing service management standard after validating metrics. Do not make up separate physical hosts for each container: they share one host's CPU and memory.

Docker Desktop runs these Java containers inside a Linux VM. The Windows smoke test verifies the application and APM wiring; Boston is the appropriate environment to validate Linux host hardware semantics. A Windows Machine Agent would describe the Windows host, not the Linux VM's kernel or its individual containers.

Confirm hardware paths in the Controller Metric Browser and through the API before running the ETL. Server Visibility settings can change where machine metrics appear. Separate Database Agent/collector setup is needed for PostgreSQL server metrics; Java JDBC timing does not replace it.

## Migration checks

- Three healthy Java services and PostgreSQL; portal reachable through SSH.
- The expected application, tiers, and new Boston node identities in AppDynamics.
- Distinct Windows and Boston host IDs if both stacks run simultaneously.
- Calls, response times, errors and JVM values during the selected ETL extraction interval.
- Host hardware values only after the Linux Machine Agent is connected and mapped.
- Existing ETL API authentication, application filters and sample interval set for the trial.

After moving the workload, stop the Windows load generator if you want only Boston traffic in the same application. Controller history remains available according to the trial's retention policy.
