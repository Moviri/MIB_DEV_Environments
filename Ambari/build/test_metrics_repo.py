"""Check per-host Metrics repository verification without Docker or network."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-metrics-repo.sh"


class MetricsRepositoryTests(unittest.TestCase):
    def verify(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            docker = Path(directory) / "docker"
            docker.write_text("""#!/bin/bash
[[ "$1 $2 $3" == 'compose exec -T' && " $* " == *' --enablerepo=test-repo '* ]] || exit 2
echo "$4" >> "$HOST_LOG"
if [[ "$4" == bigtop-hostname2 && "$MODE" == unavailable ]]; then exit 1; fi
for name in ambari-metrics-{monitor,collector,hadoop-sink,grafana}; do
    if [[ "$4" == bigtop-hostname2 && "$MODE" == missing && "$name" == *collector ]]; then
        echo "${name}-debug"
    else
        echo "$name"
    fi
done
""")
            docker.chmod(0o755)
            log = Path(directory) / "hosts"
            result = subprocess.run(
                ["bash", str(SCRIPT), "test-repo"],
                env={**os.environ, "PATH": directory + ":" + os.environ["PATH"],
                     "HOST_LOG": str(log), "MODE": mode},
                capture_output=True, text=True,
            )
            return result, log.read_text().splitlines()

    def test_all_packages_on_all_hosts(self):
        result, hosts = self.verify("complete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(hosts, [f"bigtop-hostname{i}" for i in range(4)])

    def test_missing_exact_name_or_failed_query(self):
        for mode in ("missing", "unavailable"):
            with self.subTest(mode=mode):
                result, hosts = self.verify(mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(hosts[-1], "bigtop-hostname2")
