"""Exercise the actual Apple workflow manifest selectors with both owners."""
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = [
    'apple-secure-distribution-relay.yml',
    'apple-iphone-secure-distribution-relay.yml',
    'apple-ipad-secure-distribution-relay.yml',
    'apple-post-deployment-smoke.yml',
    'apple-iphone-post-deployment-smoke.yml',
    'apple-ipad-post-deployment-smoke.yml',
]


class AppleRepositoryManifestIdentityTests(unittest.TestCase):
    def test_release_and_cleanup_target_transferred_source_repository(self):
        for filename in ('release.sh', 'cleanup_old_releases.sh'):
            with self.subTest(filename=filename):
                source = (ROOT / filename).read_text()
                self.assertIn('--repo djconnect-music-dj/djconnect-app', source)
                self.assertNotIn('--repo pcvantol/djconnect-app', source)

    def test_only_current_repository_and_exact_source_match(self):
        source = 'a' * 40
        old = 'pcvantol/djconnect-app'
        new = 'djconnect-music-dj/djconnect-app'
        manifest = {'repositories': [
            {'repository': old, 'source_sha': source, 'version': '4.0.0'},
            {'repository': new, 'source_sha': 'b' * 40, 'version': '4.1.0'},
        ]}
        for name in WORKFLOWS:
            with self.subTest(workflow=name):
                text = (ROOT / '.github/workflows' / name).read_text()
                self.assertIn('--arg repo "$GITHUB_REPOSITORY"', text)
                expressions = re.findall(r"'((?:\.repositories\[\]).*?select\(\.repository == \$repo.*?)(?:'\s+\"\$manifest\")", text)
                self.assertEqual(len(expressions), 1)
                expression = expressions[0]
                def select(repository, sha, version):
                    return subprocess.run(
                        ['jq', '-c', '--arg', 'repo', repository, '--arg', 'sha', sha, '--arg', 'version', version, expression],
                        input=json.dumps(manifest), text=True, capture_output=True, check=True,
                    ).stdout.strip()
                self.assertTrue(select(old, source, '4.0.0'))
                self.assertFalse(select(new, source, '4.1.0'))
                self.assertTrue(select(new, 'b' * 40, '4.1.0'))
                self.assertFalse(select(new, 'b' * 40, '4.0.0'))
                self.assertFalse(select('other/djconnect-app', source, '4.0.0'))


    def test_ipad_smoke_artifact_is_json_for_each_device(self):
        workflow = (ROOT / '.github/workflows/apple-ipad-post-deployment-smoke.yml').read_text()
        evidence_script, = re.findall(r'        run: \|\n          ([^\n]+apple-ipad-smoke-evidence\.json)\n', workflow)
        for target in ('ipad', 'ipad-mini'):
            with self.subTest(target=target), tempfile.TemporaryDirectory() as scratch:
                subprocess.run(['bash', '-ec', evidence_script], cwd=scratch,
                               env={**os.environ, 'TARGET_DEVICE': target}, check=True)
                evidence = json.loads((Path(scratch) / 'apple-ipad-smoke-evidence.json').read_text())
                self.assertEqual(evidence['target_device'], target)
                self.assertEqual(evidence['final_result'], 'SMOKE_PASSED')


if __name__ == '__main__':
    unittest.main()
