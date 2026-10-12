#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Exercise personal upstream merging in disposable local Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "Tools/sync-personal-upstream.sh"


class PersonalUpstreamTests(unittest.TestCase):
    def git(self, repo, *args):
        return subprocess.check_output(["git", "-C", str(repo), *args], text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def commit(self, repo, name, value):
        (repo / name).write_text(value)
        self.git(repo, "add", name)
        self.git(repo, "commit", "-m", name)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.upstream = root / "upstream"
        self.upstream.mkdir()
        self.git(self.upstream, "init", "-b", "main")
        self.git(self.upstream, "config", "user.name", "Test")
        self.git(self.upstream, "config", "user.email", "test@example.com")
        for name in ["scroll", "bluetooth", "shared"]:
            self.commit(self.upstream, name, "base\n")
        self.personal = root / "personal"
        subprocess.run(["git", "clone", str(self.upstream), str(self.personal)],
                       check=True, capture_output=True)
        self.git(self.personal, "config", "user.name", "Test")
        self.git(self.personal, "config", "user.email", "test@example.com")
        self.commit(self.personal, "scroll", "personal scroll\n")
        self.commit(self.personal, "bluetooth", "personal bluetooth\n")
        self.summary = root / "summary.md"
        self.output = root / "output"

    def sync(self, ref="main"):
        env = dict(os.environ, PERSONAL_UPSTREAM_URL=str(self.upstream),
                   PERSONAL_UPSTREAM_REF=ref, GITHUB_STEP_SUMMARY=str(self.summary),
                   GITHUB_OUTPUT=str(self.output))
        return subprocess.run(["bash", str(SCRIPT)], cwd=self.personal, env=env,
                              capture_output=True, text=True)

    def test_new_upstream_preserves_both_personal_changes(self):
        self.commit(self.upstream, "new-feature", "upstream update\n")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.personal / "new-feature").read_text(), "upstream update\n")
        self.assertEqual((self.personal / "scroll").read_text(), "personal scroll\n")
        self.assertEqual((self.personal / "bluetooth").read_text(), "personal bluetooth\n")
        self.assertIn("source_sha=" + self.git(self.personal, "rev-parse", "HEAD"), self.output.read_text())
        self.git(self.personal, "merge-base", "--is-ancestor", self.git(self.upstream, "rev-parse", "HEAD"), "HEAD")

    def test_unchanged_upstream_does_not_create_commit(self):
        before = self.git(self.personal, "rev-parse", "HEAD")
        self.assertEqual(self.sync().returncode, 0)
        self.assertEqual(self.git(self.personal, "rev-parse", "HEAD"), before)

    def test_conflict_reports_file_and_restores_personal_head(self):
        self.commit(self.personal, "shared", "personal\n")
        self.commit(self.upstream, "shared", "upstream\n")
        before = self.git(self.personal, "rev-parse", "HEAD")
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("::error", result.stdout)
        self.assertIn("shared", self.summary.read_text())
        self.assertEqual(self.git(self.personal, "rev-parse", "HEAD"), before)
        self.assertEqual(self.git(self.personal, "status", "--porcelain"), "")
        self.assertFalse(self.output.exists())

    def test_fetch_failure_does_not_modify_personal_source(self):
        before = self.git(self.personal, "rev-parse", "HEAD")
        self.assertNotEqual(self.sync("missing-branch").returncode, 0)
        self.assertEqual(self.git(self.personal, "rev-parse", "HEAD"), before)


if __name__ == "__main__":
    unittest.main()
