"""Exercise launcher repair and resume without touching a real database."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().parent
SCRIPTS = BUILD.parent / "scripts"


class ServerConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ambari-config-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.launcher = self.root / "launcher"
        self.backup = self.root / "launcher.before-buildnumber-fix"
        self.launcher.write_text(
            (BUILD / "fixtures/ambari-server-launcher-header.sh").read_text()
            .replace("${ambariFullVersion}", "3.0.0.0-0")
        )
        self.properties = self.root / "ambari.properties"
        self.properties.write_text("other.property=keep\nserver.jdbc.url=old\n")
        shutil.copyfile(SCRIPTS / "install-ambari-server-script.sh", self.root / "install.sh")
        configure = (SCRIPTS / "configure-ambari-server-script.sh").read_text()
        configure = configure.replace("/usr/sbin/ambari-server", str(self.launcher))
        configure = configure.replace("/etc/ambari-server/conf/ambari.properties", str(self.properties))
        (self.root / "configure-ambari-server-script.sh").write_text(configure)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Any accidental database/package/service step must fail the test.
        for name in ("mysql", "mysqld", "yum", "systemctl", "ambari-server", "wget"):
            stub = self.bin / name
            code = 0 if name in ("ambari-server", "wget") else 99
            stub.write_text(
                '#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n'
                f'exit {code}\n'
            )
            stub.chmod(0o755)
        self.log = self.root / "calls"
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "CALL_LOG": str(self.log)}
        self.env.pop("buildNumber", None)

    def run_setup(self):
        return subprocess.run(["bash", str(self.root / "install.sh"), "--configure-only"],
                              env=self.env, capture_output=True, text=True)

    def test_repair_and_resume_preserve_schema_and_original_launcher(self):
        original = self.launcher.read_bytes()
        broken = subprocess.run(["bash", str(self.launcher), "--hash"],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(broken.returncode, 0)
        self.assertIn("buildNumber: unbound variable", broken.stderr)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("source-archive-3.0.0", result.stdout)
        self.assertEqual(self.backup.read_bytes(), original)
        self.assertEqual([line.split()[0] for line in self.log.read_text().splitlines()],
                         ["wget", "ambari-server", "ambari-server", "ambari-server"])
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.backup.read_bytes(), original)
        self.assertEqual(self.properties.read_text().count("server.jdbc.url="), 1)
        self.assertIn("other.property=keep", self.properties.read_text())

    def test_real_build_hash_is_preserved(self):
        original = self.launcher.read_text().replace("${buildNumber}", "abc1234")
        self.launcher.write_text(original)
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.launcher.read_text(), original)
        self.assertFalse(self.backup.exists())

    def test_unexpected_version_is_rejected_before_configuration(self):
        self.launcher.write_text(self.launcher.read_text().replace("3.0.0.0-0", "9.0.0"))
        original = self.launcher.read_bytes()
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected Ambari version", result.stderr)
        self.assertEqual(self.launcher.read_bytes(), original)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
