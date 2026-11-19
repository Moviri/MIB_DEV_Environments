# Four-node Ambari development cluster

This procedure deploys Ambari 3.0.0 on Rocky Linux 8 with HDFS, YARN, MapReduce2,
ZooKeeper and Ambari Metrics. It builds packages once. Other engineers can use
the same finalized RPM bundle on their own hosts.

## 1. Prepare a clean host

Use a separate Linux x86_64 machine with Docker Engine and the Compose v2 plugin.
The Compose project uses fixed container names and host ports 8080 and 3000.
Keep the existing cluster available until its replacement passes your ETL test.
The AWS development configuration has 8 vCPUs and 32 GiB RAM. For a source build,
allow about 100 GB free for the core stack plus headroom for Metrics and Docker.
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

**If you have a finalized bundle from this version**, copy it to the clean host
and extract it from `Ambari/` into an empty destination:

```bash
tar -xf /path/to/ambari-rocky8-rpms.tar -C .
```

**To build the bundle from source**, use a persistent terminal session on the
build host. The command stops at the first failed stage. Each compilation stage
writes its own log under `.package-build/logs/`.

```bash
export AMBARI_BUILD_JOBS=2
bash build-packages.sh all
```

To verify a build from scratch, use `bash build-packages.sh all --no-cache`
in a new checkout with the default work and output paths. This mode refuses
existing build data, checks the pinned base images and disables Docker's build
cache for each builder invocation. The stages can share downloads created
during this run. An earlier checkout and its RPMs can stay in place if the
build host has room for both.

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

1. Choose the Bigtop 3.3.0 stack and the Red Hat 8 repository. Use
   `http://bigtop-hostname0.demo.local/` as the base URL.
2. Enter these target hosts and use manual registration (the agents are already
   installed and started). Confirm all four register before continuing.

   ```text
   bigtop-hostname0.demo.local
   bigtop-hostname1.demo.local
   bigtop-hostname2.demo.local
   bigtop-hostname3.demo.local
   ```

3. Select **HDFS, YARN, MapReduce2, ZooKeeper and Ambari Metrics**. The Ranger
   plugins and HBase RPM are available for dependent components even with the
   Ranger and HBase services unselected. For the tested host assignments put
   Metrics Grafana on node 0 and Metrics Collector on node 2.
4. Complete the install and start the services. Run the HDFS, YARN, MapReduce2,
   ZooKeeper and Ambari Metrics service checks. Check Grafana from the host:

   ```bash
   docker compose exec -T bigtop-hostname0 curl -fsS http://127.0.0.1:3000/api/health
   ```

   Look for `"database": "ok"`. Verify recent metrics in Grafana and run the
   same ETL used on the working cluster before switching to this instance.

For the existing Windows workflow, copy the finalized bundle into
`Ambari/ambari-repo/`, run `docker compose up -d` on a fresh Docker host and
then run `.\run.ps1` from PowerShell.
