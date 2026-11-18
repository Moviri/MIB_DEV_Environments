# Rebuilding the Rocky Linux 8 RPM repository

This workflow builds Ambari 3.0.0 server/agent and selected Bigtop 3.3.0
components without using apache-ambari.com. It uses the Apache source archives,
checks their pinned SHA-512 hashes, and runs in a digest-pinned Bigtop Rocky 8
x86_64 build container. Java 17 is selected for Ambari and Java 8 for Bigtop.

**Validation status:** the AWS host reported successful Ambari and Bigtop
builds and finalized a local repository containing 46 RPMs. Fresh installation
then successfully started MySQL and imported the Ambari schema after correcting
log ownership. The next blocker was an unresolved `${buildNumber}` in the
installed server launcher. The launcher repair and configuration-only resume
path pass local tests; server startup and full cluster validation remain pending.

## Build host

Use a Linux x86_64 host with Docker, Bash, curl/network access from containers,
and `flock` (util-linux). Debian on the existing AWS host is fine: Rocky 8 runs
inside Docker. Start with 8 CPUs, 16 GB RAM and about **100 GB free space** for
the core stack. This is a planning estimate, not a measured maximum. Additional
services can require substantially more disk. Check both the work filesystem
and Docker's storage filesystem; a large source volume alone does not enlarge
Docker storage. Avoid running the cluster while compiling if memory is tight.

The build downloads Maven/npm dependencies and component sources from upstream;
it is not an offline build. Old dependency URLs may need additional repairs.
Use a persistent terminal session on AWS for long builds.

## Core cluster: HDFS, YARN/MapReduce and ZooKeeper

From `Ambari/` on the build host:

```bash
# Optional: put sources and caches on a larger mounted disk.
# export AMBARI_BUILD_WORK=/mnt/build-disk/ambari-build
# export AMBARI_BUILD_OUTPUT=/mnt/build-disk/ambari-repo
export AMBARI_BUILD_JOBS=2

bash build-packages.sh preflight
bash build-packages.sh ambari
bash build-packages.sh bigtop
bash build-packages.sh repo
```

Run each command only after the preceding one succeeds. The default Bigtop
selection is `bigtop-select hadoop zookeeper`. Hadoop supplies HDFS, YARN and
MapReduce packages. Bigtop's build dependency graph adds its prerequisites.
The build uses `-PparentDir=/usr/bigtop -PpkgSuffix`, which is required for
Ambari's versioned package names and `/usr/bigtop/3.3.0` layout.

### Retrying a Catalog frontend Node engine failure

Hadoop 3.3.6's Application Catalog has no Yarn lockfile. Its `apidoc@0.17.7`
dependency allows newer Winston logging dependencies: these can now pull in
`color@5.0.3` (Node >=18), while the frontend build uses Node 12.22.1.
The error is reported as a failed Yarn install
and then as a failed Hadoop RPM build.

The builder applies `patch9999-ambari-catalog-node12.diff` through Bigtop's
existing RPM patch mechanism, after its bundled
`patch8-YARN-11528-triple-beam.diff`. It adds `winston@3.3.3` and
`@dabh/diagnostics@2.0.3` to the existing Yarn resolutions while preserving
Bigtop's `triple-beam@1.3.0` pin. Engine checks stay enabled, and the separate
YARN UI is unchanged. A regression test applies both patches in this order.
This is a compatibility repair, not a full dependency lock or security update.

This also recovers from `Hunk #1 FAILED` in an earlier version of the Catalog
patch, which incorrectly expected a manifest without Bigtop's resolutions.

After pulling the fix, retry only the Bigtop stage:

```bash
bash build-packages.sh bigtop
```

The changed patch invalidates only Hadoop's `.srpm` and `.rpm` completion
markers. Bigtop recreates Hadoop's RPM build tree to apply the patch; Maven
cache, source downloads, completed prerequisite packages and Ambari RPMs are
preserved. Do not edit Hadoop's generated `target/package.json`: rpmbuild would
replace it. After Bigtop succeeds, run the `repo` stage as usual.

To build additional services, supply the same selection to `bigtop` and `repo`:

```bash
bash build-packages.sh bigtop hadoop zookeeper hbase hive tez spark kafka
bash build-packages.sh repo hadoop zookeeper hbase hive tez spark kafka
```

`bigtop-select` is always built. For the remaining components supported by the
release, see `bash build-packages.sh --help` and the component allowlist in the
script. Include every service that will be selected in Ambari's installation
wizard. The `repo` stage checks package presence, not dependency closure or
service runtime compatibility.

## Outputs and retries

Defaults are relative to `Ambari/`, even if the command runs elsewhere:

- `.package-build/downloads/`: checked release archives and resumable `.part` files.
- `.package-build/sources/`: extracted sources and compiler output.
- `.package-build/cache/`: Maven, Gradle and npm caches.
- `.package-build/logs/`: timestamped logs, including failed builds.
- `ambari-repo/ambari/` and `ambari-repo/bigtop/`: binary RPMs.

The builder runs as root; generated files may require `sudo` to manage on the
host. Re-running a failed stage preserves dependency caches. Ambari runs Maven
`clean`; Bigtop retains its completed package markers. If changing Bigtop source
or flags, use a new work/output directory to avoid reusing stale packages.

An archive hash mismatch is fatal. Inspect the download before removing its
`.part` file and retrying; the workflow never extracts an unchecked archive.
The hashes are pinned to the checksum files published alongside the two
Apache release archives. Transitive Maven/npm inputs are not fully locked.

After both build stages succeed, `repo` generates metadata, `RPM-INVENTORY.tsv`,
`SOURCE-SHA512SUMS`, `BUILDER-IMAGE.txt`, `BIGTOP-COMPONENTS.txt`, and
`LOCAL_RPMS.sha256`. A new build invalidates that last file until `repo` succeeds
again. Do not run installation concurrently with a package build.

## Install into a fresh environment

If building on another host or using `AMBARI_BUILD_OUTPUT`, copy the **entire
output directory contents** to the installation host's `Ambari/ambari-repo/`,
including the checksum manifest. Use an empty destination so older RPMs are
not mixed into the new repository. Preserve the package subdirectories.

```bash
cd ambari-repo
sha256sum --strict -c LOCAL_RPMS.sha256
cd ..
docker compose up -d
bash run.sh
```

`setup-ambari-repo-script.sh` detects `LOCAL_RPMS.sha256`, checks it, and skips
both apache-ambari.com downloads. The same behavior applies to the PowerShell
launcher because it invokes the same container script. No manifest means the
original remote-download path is used.

### Resume after a successful database schema import

If installation imported the Ambari schema but stopped with
`/usr/sbin/ambari-server: line 34: buildNumber: unbound variable`, pull the fix
and run from `Ambari/`:

```bash
git pull --ff-only
(
  cd scripts &&
  bash install-ambari-server.sh --configure-only &&
  bash install-ambari-agent.sh
)
```

This resumes JDBC registration, server configuration and startup without
recreating databases or importing the schema again. It repairs only the known
Ambari `3.0.0.0-0` launcher placeholder, preserving the original launcher as
`/usr/sbin/ambari-server.before-buildnumber-fix`. No RPM rebuild is required
for this recovery; the installed file changes, while the RPM bundle stays intact.

Future archive builds pass `-DbuildNumber=source-archive-3.0.0` to Maven and
check the generated launcher's `--version` and `--hash` before copying RPMs.
The identifier explicitly denotes a source archive, not a Git commit hash.
Existing RPM bundles still need the installation-time repair unless rebuilt.

Use a **fresh cluster** for validation. The existing server setup imports the
Ambari database schema and is not a general-purpose upgrade/recovery script.
Verify that all four agents register, install only the built services, run
their service checks, and verify an HDFS read/write and a YARN job. Save the
RPM bundle once this succeeds. Package compilation alone does not prove a
working deployment, and the build commands skip upstream test suites.

## Ambari Metrics requires a separate compatibility decision

The archived **Ambari Metrics 3.0.0** release contains Python 2 monitor code
(for example, Python 2 `print` statements in `src/main/python/main.py`). This
environment sets `/usr/bin/python` to Python 3. Therefore these scripts do not
build Metrics or claim to reproduce the original mirror's Metrics binaries.
Leave Ambari Metrics unselected during the initial core-cluster validation.

To restore monitoring, identify and pin a Python 3-compatible Metrics revision,
validate its embedded HBase/Hadoop/Phoenix dependencies, and build/test the
collector, monitor, sink and Grafana packages separately. Do not substitute the
older release just because its version number also reads 3.0.0.

## Upstream references

- [Ambari 3.0.0 source and checksums](https://archive.apache.org/dist/ambari/ambari-3.0.0/)
- [Bigtop 3.3.0 source and checksums](https://archive.apache.org/dist/bigtop/bigtop-3.3.0/)
- [Ambari source build guide](https://ambari.apache.org/docs/3.0.0/ambari-dev/building-from-source/)
- [Ambari-compatible Bigtop packaging guide](https://ambari.apache.org/docs/3.0.0/ambari-dev/bigtop-guide/)

The Bigtop Git tag is `rel/3.3.0` (commit
`d44a5845eeffe6bab7037a3ca816cf3c9df44029`); the `release-3.3.0` tag shown in the
guide does not exist. The build above uses the checksummed release archive.
