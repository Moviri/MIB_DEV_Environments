"""Exercise the fresh entry point without creating containers or a database."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FreshInstallTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        shutil.copy2(ROOT / "run.sh", self.root / "run.sh")
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ("setup-ambari-repo", "setup", "install-ambari-server",
                     "install-ambari-agent", "verify-metrics-repo"):
            (scripts / f"{name}.sh").write_text('echo "${0##*/} $*" >> "$CALLS"\n')
        self.repo = self.root / "ambari-repo"
        self.repo.mkdir()
        self.log = self.root / "calls"
        docker = self.root / "docker"
        docker.write_text('#!/bin/bash\necho "$*" >> "$CALLS"\n'
                          'if [[ $2 == ps ]]; then echo "$EXISTING"; fi\n')
        docker.chmod(0o755)

    def run_fresh(self, existing=""):
        return subprocess.run(
            [str(self.root / "run.sh"), "--fresh"], cwd="/",
            env={**os.environ, "PATH": f"{self.root}:{os.environ['PATH']}",
                 "CALLS": str(self.log), "EXISTING": existing},
            capture_output=True, text=True)

    def bundle(self, release):
        groups = ["ambari-server", "ambari-agent", "bigtop-select", "hadoop_3_3_0",
                  "zookeeper_3_3_0", "hbase_3_3_0", "ranger_3_3_0-hdfs-plugin",
                  "ranger_3_3_0-yarn-plugin"]
        rows = [f"{pkg}\t1\t1\tx86_64\n" for pkg in groups]
        rows += [f"ambari-metrics-{suffix}\t3.1.0\t{release}\tx86_64\n"
                 for suffix in ("collector", "monitor", "hadoop-sink", "grafana")]
        (self.repo / "RPM-INVENTORY.tsv").write_text("".join(rows))
        rpm = self.repo / "example.rpm"
        rpm.write_bytes(b"package fixture")
        digest = hashlib.sha256(rpm.read_bytes()).hexdigest()
        (self.repo / "LOCAL_RPMS.sha256").write_text(f"{digest}  example.rpm\n")

    def test_existing_project_stops_before_install(self):
        self.bundle(2)
        self.assertNotEqual(self.run_fresh("existing-container").returncode, 0)
        self.assertEqual(self.log.read_text().splitlines(), ["compose ps --all --quiet"])

    def test_missing_bundle_or_old_release_stops_before_install(self):
        self.assertNotEqual(self.run_fresh().returncode, 0)
        self.bundle(1)
        self.assertNotEqual(self.run_fresh().returncode, 0)
        self.assertNotIn("compose up", self.log.read_text())

    def test_corrupt_bundle_stops_before_creating_containers(self):
        self.bundle(2)
        (self.repo / "example.rpm").write_bytes(b"damaged")
        self.assertNotEqual(self.run_fresh().returncode, 0)
        self.assertNotIn("compose up", self.log.read_text())

    def test_bootstrap_then_checks_repo_on_new_cluster(self):
        self.bundle(2)
        result = self.run_fresh()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log.read_text().splitlines(), [
            "compose ps --all --quiet", "compose up -d", "setup-ambari-repo.sh ",
            "setup.sh ", "install-ambari-server.sh ", "install-ambari-agent.sh ",
            "verify-metrics-repo.sh ambari"])
