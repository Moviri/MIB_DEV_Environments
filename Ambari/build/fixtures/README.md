These upstream fixtures reproduce the Catalog patch order without Docker or
network access. Both originate from Apache projects licensed under Apache 2.0.

- `hadoop-3.3.6-catalog-package.json`: [Hadoop 3.3.6 source manifest](https://github.com/apache/hadoop/blob/rel/release-3.3.6/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-webapp/package.json).
- `patch8-YARN-11528-triple-beam.diff`: [Bigtop 3.3.0 bundled patch](https://github.com/apache/bigtop/blob/d44a5845eeffe6bab7037a3ca816cf3c9df44029/bigtop-packages/src/common/hadoop/patch8-YARN-11528-triple-beam.diff).

The regression test applies the bundled Bigtop patch before the local patch,
checks that patching succeeds with zero fuzz, and rejects duplicate JSON keys.

`ambari-server-launcher-header.sh` is the header and early `--version`/`--hash`
dispatch from the Apache 2.0 licensed [Ambari 3.0.0 launcher](https://github.com/apache/ambari/blob/release-3.0.0/ambari-server/sbin/ambari-server).
Configuration tests use its actual unset-variable behavior while stubbing
package, database, network, and server commands.

`ambari-agent-launcher-header.sh` contains the equivalent early dispatch from
the Apache 2.0 licensed [Ambari 3.0.0 agent launcher](https://github.com/apache/ambari/blob/release-3.0.0/ambari-agent/conf/unix/ambari-agent).
Agent tests reproduce the unresolved hash and exercise startup decisions for
running, stopped, stale-PID and unexpected-error status codes.
