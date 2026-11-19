"""Check retry safety for Bigtop's cached source and binary RPM builds."""

from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest


BUILD = Path(__file__).resolve().parent
PATCH = "patch9999-ambari-catalog-node12.diff"
CATALOG = Path(
    "hadoop-yarn-project/hadoop-yarn/hadoop-yarn-applications/"
    "hadoop-yarn-applications-catalog/hadoop-yarn-applications-catalog-webapp/package.json"
)


class BigtopPatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bigtop-patches-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.packaging = self.root / "bigtop-packages/src/common/hadoop"
        self.packaging.mkdir(parents=True)
        self.ranger_packaging = self.packaging.parent / "ranger"
        self.ranger_packaging.mkdir()
        self.ranger_driver = self.ranger_packaging / "do-component-build"
        self.ranger_driver.write_text("mvn clean compile package install \\\n    -DskipTests=true\n")
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

    def test_ranger_patch_invalidates_only_ranger_on_retry(self):
        shutil.copyfile(BUILD / "patches" / PATCH, self.packaging / PATCH)
        # A build with the earlier Kylin fix still needs the new assembly input.
        kylin = "patch9999-ambari-kylin-linq4j.diff"
        shutil.copyfile(BUILD / "patches" / kylin, self.ranger_packaging / kylin)
        ranger_markers = [self.root / "build/ranger" / name for name in (".srpm", ".rpm")]
        ranger_markers[0].parent.mkdir(parents=True)
        for marker in ranger_markers:
            marker.touch()
        self.run_helper()
        assembly = "patch9999-ambari-ranger-distro-assembly.diff"
        self.assertEqual(self.ranger_driver.read_text(), "mvn clean install \\\n    -DskipTests=true\n")
        self.assertEqual((self.ranger_packaging / assembly).read_bytes(),
                         (BUILD / "patches" / assembly).read_bytes())
        self.assertTrue(all(marker.exists() for marker in self.markers))
        self.assertTrue(all(not marker.exists() for marker in ranger_markers))
        for marker in ranger_markers:
            marker.touch()
        self.run_helper()
        self.assertTrue(all(marker.exists() for marker in ranger_markers))

    def test_catalog_patch_applies_after_bigtop_triple_beam_patch(self):
        package = self.root / CATALOG
        package.parent.mkdir(parents=True)
        shutil.copyfile(BUILD / "fixtures/hadoop-3.3.6-catalog-package.json", package)
        self.run_helper()
        # Match Bigtop's order: its bundled patch adds resolutions first.
        for patch in (BUILD / "fixtures/patch8-YARN-11528-triple-beam.diff",
                      self.packaging / PATCH):
            result = subprocess.run(
                ["patch", "--batch", "--fuzz=0", "-p1", "-i", str(patch)],
                cwd=self.root, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        def unique_keys(pairs):
            keys = [key for key, _ in pairs]
            self.assertEqual(len(keys), len(set(keys)), "Duplicate JSON keys")
            return dict(pairs)

        actual = json.loads(package.read_text(), object_pairs_hook=unique_keys)
        self.assertEqual(actual.pop("resolutions"), {
            "winston": "3.3.3", "@dabh/diagnostics": "2.0.3", "triple-beam": "1.3.0",
        })
        original = json.loads((BUILD / "fixtures/hadoop-3.3.6-catalog-package.json").read_text())
        self.assertEqual(actual, original)


if __name__ == "__main__":
    unittest.main()
