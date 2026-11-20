# Four-node Ambari development cluster

This procedure deploys Ambari 3.0.0 on Rocky Linux 8 with HDFS, YARN, MapReduce2,
ZooKeeper and Ambari Metrics. It builds packages once. Other engineers can use
the same finalized RPM bundle on their own hosts.

## 1. Prepare a clean host

Use a separate Linux x86_64 machine with Docker Engine and the Compose v2 plugin.
The Compose project uses fixed container names and host ports 8080 and 3000.
Keep the existing cluster available until its replacement passes your ETL test.
The [AWS instance configuration](#aws-instance-configuration) below records the
host used for this deployment. For a source build, allow about 100 GB free for
the core stack plus headroom for Metrics and Docker.
Check both the checkout filesystem and Docker's data directory. Builds and
installation need outbound network access for upstream dependencies and OS packages.

Clone this repository and change to its `Ambari/` directory. While PR #4 is open:

```bash
git clone --branch feat-ambari-source-build https://github.com/Moviri/MIB_DEV_Environments.git
cd MIB_DEV_Environments/Ambari
docker compose version
docker info --format '{{.DockerRootDir}}'
df -h .
```

## 2. Prepare the RPM repository

**Build from source on a fresh clone.** From `Ambari/` on the build host, use a
persistent terminal session. This is the command used for the successful
four-node AWS installation and ETL test.

```bash
export AMBARI_BUILD_JOBS=2
bash build-packages.sh all --no-cache
```

The stages run in order: preflight, Ambari server and agent, Bigtop, Python 3
Ambari Metrics, then RPM repository finalization. The command requires empty
work and output directories, rebuilds the builder images without cached layers,
and writes stage logs under `.package-build/logs/`. Success produces
`ambari-repo/LOCAL_RPMS.sha256` and `ambari-repo/RPM-INVENTORY.tsv`.
For a build that can reuse existing downloads and build state, omit `--no-cache`.

**Reuse a finalized bundle** when testing another deployment of the same Git
revision. Copy the archive to the new machine and extract it into the fresh
checkout from `Ambari/`:

```bash
tar -xf /path/to/ambari-rocky8-rpms.tar -C .
```

To resume a completed core build, run `bash build-packages.sh metrics && bash
build-packages.sh repo` in the same checkout with the original output directory.
The final bundle includes the Ranger plugins and HBase required by YARN and the
four Python 3-compatible Metrics packages at release `3.1.0-2`. To share it,
archive it **on the build host** from `Ambari/`:

```bash
tar -cf ambari-rocky8-rpms.tar ambari-repo/
```

Use the same Git revision for deployment. See the [build guide](build/README.md)
for individual stages, extended service selections, disk settings and recovery.

## 3. Bootstrap and install

On the **clean host**, from `Ambari/`:

```bash
./run.sh --fresh
```

This checks the local package inventory, creates the four containers, verifies
RPM checksums, serves the repository from node 0, configures MySQL and starts
Ambari Server and the four agents. It checks that every node can resolve the
Metrics packages before the wizard. If the Compose project already has
containers, the fresh command stops before starting the installer.

Open the Ambari UI on port 8080 (initial login `admin` / `admin`). For a remote
VM, you can run `ssh -L 8080:localhost:8080 admin@YOUR_EC2_HOST` from your
workstation, then open [the local Ambari UI](http://localhost:8080).

For the tested wizard path, continue below. To trial the same topology through
the API, go straight to [Install from the blueprint](#install-from-the-blueprint)
after bootstrap.

### Wizard host registration and node 0's private key

1. Choose **BIGTOP 3.3.0** and the **Red Hat 8** repository. Set its base URL to
   `http://bigtop-hostname0.demo.local/`.
2. Enter the following target hosts. Select **Perform manual registration on
   hosts and do not use SSH**. Bootstrap already started the agents. Leave the
   SSH key field empty and confirm all four hosts register.

   ```text
   bigtop-hostname0.demo.local
   bigtop-hostname1.demo.local
   bigtop-hostname2.demo.local
   bigtop-hostname3.demo.local
   ```

If you choose the wizard's **SSH registration** option instead, use the current
node 0 container's `/root/.ssh/id_rsa` with SSH user `root`. Setup generates a
new key on each run. To save it to a private temporary file on the Docker host for this wizard run:

```bash
keyfile=$(mktemp) && docker compose exec -T bigtop-hostname0 cat /root/.ssh/id_rsa > "$keyfile" && echo "$keyfile"
```

Use that file for SSH registration and remove it afterward with `rm -- "$keyfile"`. Manual
registration and blueprint deployment both work without exporting the key.

### Minimum services and host assignments

Select **HDFS** as the file system and **YARN, MapReduce2, ZooKeeper, and Ambari
Metrics** as services. Leave the other services unchecked. The build includes
HBase and the Ranger plugins because the selected services require their RPMs.

Use these assignments on **Assign Masters** and **Assign Slaves and Clients**.
Node numbers refer to the four FQDNs above.

| Node | Assigned masters | DataNode | Router | NodeManager | Client |
| --- | --- | --- | --- | --- | --- |
| 0 | NameNode, ResourceManager, Timeline Reader, YARN Registry DNS, ZooKeeper Server, Metrics Grafana | No | No | No | Yes |
| 1 | Secondary NameNode, Timeline Service V2, MapReduce History Server, ZooKeeper Server | Yes | No | Yes | Yes |
| 2 | ZooKeeper Server, Metrics Collector | Yes | No | Yes | Yes |
| 3 | — | Yes | No | Yes | Yes |

**Client** installs the HDFS, YARN, MapReduce2 and ZooKeeper clients together.
Ambari deploys a Metrics Monitor on each host. Complete the wizard and run the
[cluster checks](#verify-the-installation).

### Install from the blueprint

Use a **separate clean Docker host** for this trial. Copy the finalized bundle
and use the same Git revision as the working cluster. Run `./run.sh --fresh`
once on the trial host, then leave the wizard at its welcome screen. The two
commands below run on that host from `Ambari/` and require Python 3.

```bash
python3 blueprint/install.py register
python3 blueprint/install.py deploy
```

Each command prompts for the trial server's Ambari admin password and checks
that the server has zero clusters and exactly the four expected agents.
`register` configures BIGTOP's Rocky 8 repository to use node 0 and submits
the [blueprint](blueprint/blueprint.json) for Ambari's topology validation.
After registration succeeds, `deploy` reads the [host mappings](blueprint/clustertemplate.json),
checks the saved repository URL, prompts for a new Grafana password, and submits
an asynchronous install-and-start request for `mov-ambari`. Follow its request
in **Background Operations**. If deployment already created a cluster, inspect
that request before retrying any failed tasks.

The files come from the wizard export for this Compose topology. The blueprint
includes all four Metrics Monitors explicitly and keeps the wizard's service
settings and internal hostnames. The template keeps the exported memory settings
(`NEVER_APPLY` for stack recommendations), so use the same host sizing for
the comparison. Saved Grafana and SSL passwords were removed.
The profile uses HTTP. Ambari inherits stack defaults for unused SSL stores
and receives a generated fallback for any missing required password. The original
ZIP and an SSH key are unnecessary for this trial.

### Verify the installation

Run the HDFS, YARN, MapReduce2, ZooKeeper and Ambari Metrics service checks.
In **Ambari Metrics → Summary**, look for **Metrics Collector: Started**,
**Grafana: Started**, and **4/4 Live Metrics Monitors**. From the trial host:

```bash
docker compose exec -T bigtop-hostname0 curl -fsS http://127.0.0.1:3000/api/health
```

Look for `"database": "ok"`, confirm recent metrics, and point the ETL at the
new endpoint. The fresh source build and wizard install passed the ETL on AWS.
The blueprint path still needs that end-to-end check.

For the existing Windows workflow, copy the finalized bundle into
`Ambari/ambari-repo/`, run `docker compose up -d` on a fresh Docker host and
then run `.\run.ps1` from PowerShell.

## AWS instance configuration

The four cluster nodes ran as Docker containers on a single EC2 instance.

| Setting | Value used |
| --- | --- |
| EC2 instance type | `m4.2xlarge` (8 vCPUs, 32 GiB RAM) |
| Host operating system | Debian 13 |
| Container operating system | Rocky Linux 8 |
| Provisioned storage | 100 GB |
| EC2 security groups | Moviri and Ambari |

## Supporting links

- [Video walkthrough used for the original setup](https://www.youtube.com/watch?v=Ao95xAGsA20)
- [Ambari 3.0 Hadoop operations course](https://github.com/call518/ambari-3.0-hadoop-ops-course) — source of the original setup scripts.
- [Apache Ambari 3.0.0 Docker environment setup](https://ambari.apache.org/docs/3.0.0/quick-start/environment-setup/docker-environment-setup)
- [Install Docker Engine and the Compose plugin on Debian](https://docs.docker.com/engine/install/debian/)
- [Rocky Linux 8 RPM build guide](build/README.md) — source archives, checksums, individual build stages, and retry instructions for this repository.
