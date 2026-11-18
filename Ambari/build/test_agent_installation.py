"""Check archive launcher recovery and running/stopped agent handling."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILD = Path(__file__).resolve().parent
SCRIPT = BUILD.parent / "scripts/install-ambari-agent-script.sh"


class AgentInstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ambari-agent-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.launcher = self.root / "launcher"
        header = (BUILD / "fixtures/ambari-agent-launcher-header.sh").read_text()
        self.launcher.write_text(header.replace("${ambariVersion}", "3.0.0.0") + '''
printf '%s\\n' "$1" >> "$AGENT_CALLS"
case "$1" in
  status) echo 'Agent currently not running'; exit "$STATUS_EXIT" ;;
  start|restart) exit "${ACTION_EXIT:-0}" ;;
  *) exit 90 ;;
esac
''')
        self.original = self.launcher.read_bytes()
        script = SCRIPT.read_text().replace("/var/lib/ambari-agent/bin/ambari-agent", str(self.launcher))
        script = script.replace("/etc/ambari-agent/conf/ambari-agent.ini", str(self.root / "agent.ini"))
        script = script.replace("/etc/yum.repos.d/ambari.repo", str(self.root / "ambari.repo"))
        (self.root / "install.sh").write_text(script)
        (self.root / "agent.ini").write_text("hostname=old\n")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("ln", "mkdir", "touch", "yum", "systemctl", "ambari-agent"):
            stub = self.bin / name
            stub.write_text('#!/bin/bash\n' + (
                'exec bash "$TEST_LAUNCHER" "$@"\n' if name == "ambari-agent" else 'exit 0\n'
            ))
            stub.chmod(0o755)
        self.calls = self.root / "calls"
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}",
                    "TEST_LAUNCHER": str(self.launcher), "AGENT_CALLS": str(self.calls)}
        self.env.pop("buildNumber", None)

    def run_install(self, status, action=0):
        return subprocess.run(["bash", str(self.root / "install.sh")], capture_output=True,
                              text=True, env={**self.env, "STATUS_EXIT": str(status), "ACTION_EXIT": str(action)})

    def test_stopped_agent_is_repaired_and_started(self):
        broken = subprocess.run(["bash", str(self.launcher), "--hash"],
                                env=self.env, capture_output=True, text=True)
        self.assertIn("buildNumber: unbound variable", broken.stderr)
        result = self.run_install(3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["status", "start"])
        backup = self.root / "launcher.before-buildnumber-fix"
        self.assertEqual(backup.read_bytes(), self.original)
        result = self.run_install(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines()[-2:], ["status", "restart"])
        self.assertEqual(backup.read_bytes(), self.original)

    def test_stale_pid_triggers_start(self):
        result = self.run_install(2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ["status", "start"])

    def test_unexpected_status_failure_is_not_swallowed(self):
        result = self.run_install(1)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls.read_text().splitlines(), ["status"])

    def test_start_failure_is_propagated(self):
        result = self.run_install(3, action=17)
        self.assertEqual(result.returncode, 17)

    def test_real_hash_is_preserved(self):
        self.launcher.write_text(self.launcher.read_text().replace("${buildNumber}", "abc1234"))
        original = self.launcher.read_bytes()
        result = self.run_install(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.launcher.read_bytes(), original)
        self.assertFalse((self.root / "launcher.before-buildnumber-fix").exists())

    def test_unexpected_version_blocks_repair_and_start(self):
        self.launcher.write_text(self.launcher.read_text().replace('VERSION="3.0.0.0"', 'VERSION="9.0.0"'))
        original = self.launcher.read_bytes()
        result = self.run_install(3)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.launcher.read_bytes(), original)
        self.assertFalse(self.calls.exists())


if __name__ == "__main__":
    unittest.main()
