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

Run one AppDynamics **Machine Agent on the host whose hardware you intend to measure** to obtain CPU, memory, disk and network data. Select an agent distribution supported on that host. Do not use a basic, isolated agent container as evidence of host hardware metrics: it can report its own namespace instead. For container visibility, use AppDynamics' documented Docker Visibility installation and its corresponding permissions/licensing.

Configure the Machine Agent's Controller settings to match the Java agents, set the **same unique host ID** as the three JVMs on this host (`capital-lab-host-02` in this example), and leave application, tier, and node name unset for this host-level installation. According to the [installation scenarios](https://help.splunk.com/appdynamics-saas/infrastructure-visibility/25.4.0/machine-agent/install-the-machine-agent/machine-agent-installation-scenarios), matching IDs allow one Machine Agent to report hardware metrics for multiple app-agent nodes.

An example foreground launch in a Unix shell after extracting a Machine Agent to `agents/machine`:

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

When Docker runs Linux containers inside a VM, distinguish the workstation's hardware from the VM's resources. For example, a Windows Machine Agent reports the Windows host; it does not describe the Linux VM's kernel or individual containers. Choose the deployment and Machine Agent placement to match the hardware data you need to validate.

Confirm hardware paths in the Controller Metric Browser and through the API before running the ETL. Server Visibility settings can change where machine metrics appear. Separate Database Agent/collector setup is needed for PostgreSQL server metrics; Java JDBC timing does not replace it.

## Migration checks

- Three healthy Java services and PostgreSQL; portal reachable through SSH.
- The expected application, tiers, and destination node identities in AppDynamics.
- Distinct source and destination host IDs if both stacks run simultaneously.
- Calls, response times, errors and JVM values during the selected ETL extraction interval.
- Host hardware values only after the Machine Agent is connected and mapped.
- Existing ETL API authentication, application filters and sample interval set for the trial.

After moving the workload, stop the source host's load generator if you want only destination traffic in the same application. Controller history remains available according to the Controller's retention policy.
