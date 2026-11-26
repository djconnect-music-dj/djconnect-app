import hashlib
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'release'))
from select_internal_ios_profile import select_profile


class InternalIOSDevelopmentProfileTests(unittest.TestCase):
    now = datetime(2026, 11, 26, tzinfo=timezone.utc)
    bundle = 'dev.djconnect.ios.track-insight-widget'
    identity = hashlib.sha1(b'fixture certificate').hexdigest().upper()

    def profile(self, days=5, **overrides):
        return {
            'Entitlements': {'application-identifier': f'TEAM.{self.bundle}', 'get-task-allow': True},
            'DeveloperCertificates': [b'fixture certificate'],
            'ProvisionedDevices': ['approved-device'],
            'ExpirationDate': (self.now + timedelta(days=days)).replace(tzinfo=None),
            **overrides,
        }

    def select(self, candidates):
        return select_profile(candidates, self.bundle, 'approved-device', self.identity, self.now)

    def test_selects_longest_lived_equivalent_profile(self):
        self.assertEqual(self.select([('older', self.profile()), ('renewed', self.profile(30))]), 'renewed')

    def test_expired_wrong_certificate_and_partial_device_do_not_contend(self):
        candidates = [
            ('expired', self.profile(0)),
            ('wrong-cert', self.profile(40, DeveloperCertificates=[b'other certificate'])),
            ('partial-device', self.profile(40, ProvisionedDevices=['other-approved-device'])),
            ('current', self.profile()),
        ]
        self.assertEqual(self.select(candidates), 'current')

    def test_conflicting_authorized_entitlements_fail_closed(self):
        different = self.profile(30)
        different['Entitlements']['aps-environment'] = 'development'
        with self.assertRaisesRegex(ValueError, 'Conflicting'):
            self.select([('current', self.profile()), ('different', different)])

    def test_exact_profile_wins_over_wildcard(self):
        wildcard = self.profile(30)
        wildcard['Entitlements']['application-identifier'] = 'TEAM.dev.djconnect.*'
        self.assertEqual(self.select([('wildcard', wildcard), ('exact', self.profile())]), 'exact')
