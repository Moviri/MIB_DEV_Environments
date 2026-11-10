"""Exercise local-bundle selection with real sha256sum and no Docker/network."""

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/setup-ambari-repo-script.sh"


class LocalRepositoryTests(unittest.TestCase):
    def run_setup(self, manifest=None, corrupt=False):
        with tempfile.TemporaryDirectory(prefix="ambari-local-repo-") as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            package = repo / "example.rpm"
            package.write_bytes(b"package fixture")
            if manifest is not None:
                content = manifest
                if manifest == "valid":
                    digest = hashlib.sha256(package.read_bytes()).hexdigest()
                    content = f"{digest}  example.rpm\n"
                (repo / "LOCAL_RPMS.sha256").write_text(content)
            if corrupt:
                package.write_bytes(b"changed after finalizing")

            stub_dir = root / "bin"
            stub_dir.mkdir()
            # Prevent package installation, downloads, and changes to host /etc.
            # sha256sum and test intentionally remain the real system commands.
            for name in ("dnf", "wget", "createrepo", "sed", "sudo", "tee", "systemctl"):
                stub = stub_dir / name
                stub.write_text('#!/bin/bash\nprintf "%s\\n" "${0##*/}" >> "$CALL_LOG"\n')
                stub.chmod(0o755)
            script = root / "setup.sh"
            script.write_text(SCRIPT.read_text().replace("cd /var/repo/ambari", f"cd '{repo}'"))
            log = root / "calls"
            result = subprocess.run(
                ["bash", str(script)],
                env={**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}", "CALL_LOG": str(log)},
                capture_output=True,
                text=True,
            )
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls

    def test_valid_local_bundle_avoids_both_downloads(self):
        result, calls = self.run_setup("valid")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("wget", calls)
        self.assertIn("createrepo", calls)
        self.assertIn("systemctl", calls)

    def test_corrupt_package_stops_before_repository_creation(self):
        result, calls = self.run_setup("valid", corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("wget", calls)
        self.assertNotIn("createrepo", calls)
        self.assertNotIn("systemctl", calls)

    def test_empty_manifest_fails_without_remote_fallback(self):
        result, calls = self.run_setup("")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("wget", calls)
        self.assertNotIn("createrepo", calls)

    def test_missing_manifest_preserves_remote_downloads(self):
        result, calls = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls.count("wget"), 2)


if __name__ == "__main__":
    unittest.main()
