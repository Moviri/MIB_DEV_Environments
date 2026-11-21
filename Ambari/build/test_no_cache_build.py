"""Verify a from-scratch build uses only its new work and Docker inputs."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "build-packages.sh"


class NoCacheBuildTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.log = self.root / "docker.log"
        docker = self.root / "docker"
        docker.write_text('#!/bin/sh\necho "$*" >> "$DOCKER_LOG"\n')
        docker.chmod(0o755)
        self.work = self.root / "work"
        self.output = self.root / "output"

    def build(self, *options):
        env = dict(os.environ, AMBARI_BUILD_WORK=str(self.work),
                   AMBARI_BUILD_OUTPUT=str(self.output), AMBARI_BUILD_MIN_GB="1",
                   PATH=f"{self.root}:{os.environ['PATH']}", DOCKER_LOG=str(self.log))
        env.pop("AMBARI_DOCKER_NO_CACHE", None)
        return subprocess.run(["bash", str(SCRIPT), "all", *options],
                              capture_output=True, text=True, env=env)

    def test_old_hidden_data_in_either_directory_stops_before_docker(self):
        for directory in (self.work, self.output):
            with self.subTest(directory=directory):
                directory.mkdir()
                marker = directory / ".keep"
                marker.touch()
                self.assertNotEqual(self.build("--no-cache").returncode, 0)
                self.assertTrue(marker.is_file())
                self.assertFalse(self.log.exists())
                marker.unlink()

    def test_clean_and_normal_docker_build_flags(self):
        self.output.mkdir()
        for options in [("--no-cache",), ()]:
            with self.subTest(options=options):
                result = self.build(*options)
                self.assertEqual(result.returncode, 0, result.stderr)
                builds = [line.split() for line in self.log.read_text().splitlines()
                          if line.startswith("build ")]
                self.assertEqual(len(builds), 4)
                for args in builds:
                    self.assertEqual("--no-cache" in args, bool(options))
                    self.assertEqual("--pull" in args, bool(options))
                self.log.unlink()
