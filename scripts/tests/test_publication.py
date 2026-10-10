"""Regression checks for publication boundaries, using disposable Git repos."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CHECK = Path(__file__).resolve().parents[1] / 'check-publication.py'


class PublicationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(('GIT_AUTHOR_', 'GIT_COMMITTER_'))}
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Public Test Author')
        self.git('config', 'user.email', 'test@users.noreply.github.com')
        self.git('config', 'commit.gpgsign', 'false')

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo,
                                       env=self.env, stderr=subprocess.PIPE)

    def write(self, name, text):
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        self.git('add', '--', name)

    def check(self, *args):
        return subprocess.run([sys.executable, str(CHECK), *args], cwd=self.repo,
                              env=self.env, text=True, capture_output=True)

    def test_clean_snapshot_and_history_pass(self):
        self.write('README.md', 'Public source project.\n')
        self.git('commit', '-qm', 'Initialize public project')
        self.assertEqual(self.check('--history').returncode, 0)

    def test_unicode_and_newline_names_cannot_hide_blocked_directory(self):
        self.write('.opencode/' + '\u79d8\u5bc6\nnotes.md', 'Internal notes.\n')
        self.assertEqual(self.check().returncode, 1)

    def test_deleted_internal_file_remains_blocked_in_history(self):
        self.write('.sisyphus/plan.md', 'Internal plan.\n')
        self.git('commit', '-qm', 'First snapshot')
        self.git('rm', '-q', '.sisyphus/plan.md')
        self.git('commit', '-qm', 'Remove internal file')
        self.assertEqual(self.check().returncode, 0)
        self.assertEqual(self.check('--history').returncode, 1)

    def test_index_is_checked_even_if_working_file_is_clean(self):
        private_path = '/' + 'Users/' + 'example/' + 'private-data'
        self.write('sample.txt', private_path)
        (self.repo / 'sample.txt').write_text('Clean working copy.\n')
        self.assertEqual(self.check().returncode, 1)

    def test_home_path_without_trailing_slash_is_rejected(self):
        self.write('sample.txt', '/' + 'home/' + 'example')
        self.assertEqual(self.check().returncode, 1)

    def test_private_commit_identity_is_rejected(self):
        self.git('config', 'user.email', 'test@' + 'gmail.com')
        self.write('README.md', 'Public source project.\n')
        self.git('commit', '-qm', 'Initialize public project')
        self.assertEqual(self.check('--history').returncode, 1)


if __name__ == '__main__':
    unittest.main()
