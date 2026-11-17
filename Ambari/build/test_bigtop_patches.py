"""Check retry safety for Bigtop's cached source and binary RPM builds."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


BUILD = Path(__file__).resolve().parent
PATCH = "patch9999-ambari-catalog-node12.diff"


class BigtopPatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bigtop-patches-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.packaging = self.root / "bigtop-packages/src/common/hadoop"
        self.packaging.mkdir(parents=True)
        self.markers = [self.root / "build/hadoop" / name for name in (".srpm", ".rpm")]
        self.preserved = [
            self.root / "build/zookeeper/.rpm",
            self.root / "cache/m2/dependency.jar",
            self.root / "output/ambari-server.rpm",
        ]
        for path in self.markers + self.preserved:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("existing build data")

    def run_helper(self):
        result = subprocess.run(
            ["bash", str(BUILD / "apply-bigtop-patches.sh"), str(self.root)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in self.preserved:
            self.assertEqual(path.read_text(), "existing build data")

    def test_new_patch_invalidates_only_hadoop_completion_markers(self):
        self.run_helper()
        self.assertTrue(all(not path.exists() for path in self.markers))
        self.assertEqual(
            (self.packaging / PATCH).read_bytes(), (BUILD / "patches" / PATCH).read_bytes()
        )

    def test_same_patch_preserves_completed_build(self):
        shutil.copyfile(BUILD / "patches" / PATCH, self.packaging / PATCH)
        self.run_helper()
        for path in self.markers:
            self.assertEqual(path.read_text(), "existing build data")

    def test_changed_patch_invalidates_previous_source_and_binary_rpms(self):
        (self.packaging / PATCH).write_text("previous patch contents")
        self.run_helper()
        self.assertTrue(all(not path.exists() for path in self.markers))
        self.assertEqual(
            (self.packaging / PATCH).read_bytes(), (BUILD / "patches" / PATCH).read_bytes()
        )


if __name__ == "__main__":
    unittest.main()
