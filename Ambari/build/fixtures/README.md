These upstream fixtures reproduce the Catalog patch order without Docker or
network access. Both originate from Apache projects licensed under Apache 2.0.

- `hadoop-3.3.6-catalog-package.json`: [Hadoop 3.3.6 source manifest](https://github.com/apache/hadoop/blob/rel/release-3.3.6/hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-webapp/package.json).
- `patch8-YARN-11528-triple-beam.diff`: [Bigtop 3.3.0 bundled patch](https://github.com/apache/bigtop/blob/d44a5845eeffe6bab7037a3ca816cf3c9df44029/bigtop-packages/src/common/hadoop/patch8-YARN-11528-triple-beam.diff).

The regression test applies the bundled Bigtop patch before the local patch,
checks that patching succeeds with zero fuzz, and rejects duplicate JSON keys.
