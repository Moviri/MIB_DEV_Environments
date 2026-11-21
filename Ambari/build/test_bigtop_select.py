"""Run the actual Bigtop selector against a temporary stack filesystem."""

import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

BUILD = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepare_select", BUILD / "prepare-bigtop-select.py")
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class BigtopSelectTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bigtop-select-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.selector = self.root / "distro-select"
        shutil.copyfile(BUILD / "fixtures/bigtop-3.3.0-distro-select.py", self.selector)
        self.selector.chmod(0o755)
        self.stack = self.root / "stack"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for version in ("3.3.0", "3.10.0"):
            for package in ("hadoop", "hadoop-hdfs", "hadoop-yarn", "hadoop-mapreduce", "zookeeper"):
                (self.stack / version / "usr/lib" / package).mkdir(parents=True)
        (self.root / "params.py").write_text(
            "stack_root = {!r}\nstack_version = '3.3.0'\n".format(str(self.stack))
        )

    def run_selector(self, *args, expected=0):
        result = subprocess.run([sys.executable, str(self.selector), *args],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout

    def prepare_commands(self):
        repair.prepare(self.selector)
        # Redirect the selector's global /usr/bin symlinks into the fixture.
        source = self.selector.read_text()
        self.selector.write_text(source.replace('bin_directory = "/usr/bin"',
                                                "bin_directory = {!r}".format(str(self.bin))))

    def test_original_error_and_backup_preserving_idempotent_repair(self):
        original = self.selector.read_bytes()
        result = subprocess.run([sys.executable, str(self.selector), "packages"],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SyntaxError", result.stderr)
        repair.prepare(self.selector, backup=True)
        repaired = self.selector.read_bytes()
        self.assertIn("hadoop-client", self.run_selector("packages"))
        repair.prepare(self.selector, backup=True)
        self.assertEqual(self.selector.read_bytes(), repaired)
        self.assertEqual((self.root / "distro-select.before-python3-fix").read_bytes(), original)
        self.assertEqual(self.selector.stat().st_mode & 0o777, 0o755)

    def test_package_queries_versions_and_status(self):
        self.prepare_commands()
        self.assertIn("zookeeper-server", self.run_selector("packages"))
        self.assertEqual(self.run_selector("versions").splitlines(), ["3.3.0", "3.10.0"])
        self.assertEqual(self.run_selector("supports", "hadoop-client").strip(), "hadoop-client")
        self.run_selector("supports", "not-a-package", expected=1)
        self.assertIn("hadoop-client - None", self.run_selector("status"))

    def test_selection_aliases_and_all_create_expected_symlinks(self):
        self.prepare_commands()
        self.run_selector("set", "hadoop-hdfs-server", "3.3.0")
        namenode = self.stack / "current/hadoop-hdfs-namenode"
        self.assertEqual(namenode.resolve(), self.stack / "3.3.0/usr/lib/hadoop-hdfs")
        self.run_selector("set", "all", "3.10.0")
        self.assertEqual(namenode.resolve(), self.stack / "3.10.0/usr/lib/hadoop-hdfs")
        self.assertIn("hadoop-hdfs-namenode - 3.10.0", self.run_selector("status"))
        self.assertTrue((self.bin / "hdfs").is_symlink())

    def test_only_select_build_markers_are_invalidated_on_change(self):
        markers = [self.root / "build/bigtop-select" / name for name in (".srpm", ".rpm")]
        other = self.root / "build/hadoop/.rpm"
        for path in markers + [other]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("complete")
        repair.prepare(self.selector, build_root=self.root)
        self.assertTrue(all(not marker.exists() for marker in markers))
        self.assertEqual(other.read_text(), "complete")
        for marker in markers:
            marker.write_text("rebuilt")
        repair.prepare(self.selector, build_root=self.root)
        self.assertTrue(all(marker.read_text() == "rebuilt" for marker in markers))

    def test_unknown_contents_fail_without_mutation(self):
        self.selector.write_text(self.selector.read_text() + "# local changes\n")
        original = self.selector.read_bytes()
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            repair.prepare(self.selector, backup=True)
        self.assertEqual(self.selector.read_bytes(), original)
        self.assertFalse((self.root / "distro-select.before-python3-fix").exists())

    def test_rpm_interpreter_rewrite_is_supported(self):
        self.selector.write_text(self.selector.read_text().replace(
            "#!/usr/bin/env python2", "#!/usr/bin/python2"))
        repair.prepare(self.selector)
        self.assertIn("hadoop-client", self.run_selector("packages"))


if __name__ == "__main__":
    unittest.main()
