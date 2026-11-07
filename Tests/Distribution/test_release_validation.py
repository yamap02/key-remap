import base64
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


APP = load('verify-release-signatures')
INSTALLER = load('verify-installer-signature')
NOTARY = load('check-notary-result')
PACKAGE_APP = load('verify-package-app')
TEAM = 'ABCDEF1234'
APP_OUTPUT = '''CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1+3 location=embedded
Authority=Developer ID Application: Test Organization (ABCDEF1234)
Authority=Developer ID Certification Authority
Timestamp=Nov 7, 2026 at 12:00:00 PM
TeamIdentifier=ABCDEF1234
'''
PKG_OUTPUT = '''Package "test.pkg":
   Status: signed by a developer certificate issued by Apple for distribution
   Signed with a trusted timestamp on: 2026-11-07 12:00:00 +0000
   Certificate Chain:
    1. Developer ID Installer: Test Organization (ABCDEF1234)
    2. Developer ID Certification Authority
'''


class ReleaseValidation(unittest.TestCase):
    def test_package_app_must_match_release_configuration(self):
        env = {'REKEY_PRODUCT_ID': 'org.vendor.rekey', 'REKEY_VERSION': '1.2.3',
               'REKEY_BUILD_NUMBER': '42', 'REKEY_FEED_URL': 'https://vendor.test/feed',
               'REKEY_ED_PUBLIC_KEY': 'public-key'}
        common = {'ReKeyProductIdentifier': env['REKEY_PRODUCT_ID'],
                  'CFBundleShortVersionString': env['REKEY_VERSION'],
                  'CFBundleVersion': env['REKEY_BUILD_NUMBER']}
        app_info = dict(common, CFBundleIdentifier=env['REKEY_PRODUCT_ID'],
                        SUFeedURL=env['REKEY_FEED_URL'], SUPublicEDKey=env['REKEY_ED_PUBLIC_KEY'],
                        SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                        SUAllowsAutomaticUpdates=False)
        agent_info = dict(common, CFBundleIdentifier=env['REKEY_PRODUCT_ID'] + '.agent')
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / 'ReKey.app'
            paths = [app / 'Contents/Info.plist',
                     app / 'Contents/Library/LoginItems/ReKeyAgent.app/Contents/Info.plist']
            def write(path, info):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(plistlib.dumps(info))
            write(paths[0], app_info)
            write(paths[1], agent_info)
            PACKAGE_APP.validate(app, env)
            for index, key, bad in ((0, 'CFBundleVersion', '41'), (0, 'SUFeedURL', 'https://other.test'),
                                    (0, 'SUPublicEDKey', 'other'), (0, 'SURequireSignedFeed', False),
                                    (1, 'CFBundleIdentifier', 'org.other.agent'), (1, 'CFBundleVersion', '41')):
                original = (app_info, agent_info)[index]
                write(paths[index], dict(original, **{key: bad}))
                with self.subTest(key=key, index=index), self.assertRaises(ValueError):
                    PACKAGE_APP.validate(app, env)
                write(paths[index], original)

    def test_app_signer_requires_team_identity_runtime_and_timestamp(self):
        APP.validate_description(APP_OUTPUT, TEAM)
        for altered in (APP_OUTPUT.replace(TEAM, 'OTHER12345'),
                        APP_OUTPUT.replace('Developer ID Application:', 'Apple Development:'),
                        APP_OUTPUT.replace('(runtime)', '(adhoc,runtime)'),
                        APP_OUTPUT.replace('(runtime)', '(none)'),
                        APP_OUTPUT.replace('Timestamp=', 'Signed Time=')):
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                APP.validate_description(altered, TEAM)

    def test_each_code_object_is_checked_against_apple_requirement(self):
        calls = []
        def fake_run(args, **kwargs):
            calls.append(args)
            return SimpleNamespace(stdout=APP_OUTPUT, stderr='')
        with patch.object(APP.subprocess, 'run', side_effect=fake_run):
            APP.verify(Path('/test/ReKey.app'), TEAM)
        requirements = [call for call in calls if '-R' in call]
        self.assertEqual(len(requirements), 9)
        for call in requirements:
            requirement = call[call.index('-R') + 1]
            self.assertIn('anchor apple generic', requirement)
            self.assertIn('1.2.840.113635.100.6.1.13', requirement)
            self.assertIn(TEAM, requirement)

    def test_package_requires_trusted_installer_and_matching_team(self):
        INSTALLER.validate_description(PKG_OUTPUT, TEAM)
        for altered in (PKG_OUTPUT.replace(TEAM, 'OTHER12345'),
                        PKG_OUTPUT.replace('Developer ID Installer:', 'Developer ID Application:'),
                        PKG_OUTPUT.replace('Signed with a trusted timestamp', 'No timestamp'),
                        PKG_OUTPUT.replace('signed by a developer certificate issued by Apple for distribution', 'no signature')):
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                INSTALLER.validate_description(altered, TEAM)

    def test_notary_must_explicitly_accept(self):
        self.assertTrue(NOTARY.accepted({'status': 'Accepted'}))
        for value in ({}, {'status': 'Invalid'}, {'status': 'In Progress'}, None, []):
            with self.subTest(value=value):
                self.assertFalse(NOTARY.accepted(value))

    def test_release_configuration_fails_closed(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith('REKEY_')}
        env.update(REKEY_RELEASE='1', REKEY_PRODUCT_ID='org.vendor.rekey', REKEY_TEAM_ID=TEAM,
                   REKEY_SIGNING_IDENTITY='Developer ID Application: Test Organization (ABCDEF1234)',
                   REKEY_VERSION='1.0.0', REKEY_BUILD_NUMBER='100',
                   REKEY_FEED_URL='https://github.com/vendor/rekey/releases/latest/download/appcast.xml',
                   REKEY_ED_PUBLIC_KEY=base64.b64encode(bytes(32)).decode())
        def check(values):
            return subprocess.run(['/bin/zsh', '-c', 'source scripts/build-config.sh'],
                                  cwd=ROOT, env=values, capture_output=True).returncode
        self.assertEqual(check(env), 0)
        for changes in ({'REKEY_TEAM_ID': ''}, {'REKEY_SIGNING_IDENTITY': '-'},
                        {'REKEY_PRODUCT_ID': 'jp.example.rekey'}, {'REKEY_PRODUCT_ID': 'org.' + 'a' * 118}, {'REKEY_VERSION': 'invalid'}, {'REKEY_BUILD_NUMBER': '01'},
                        {'REKEY_FEED_URL': 'http://example.com/feed.xml'},
                        {'REKEY_FEED_URL': 'https://example.invalid/feed.xml'},
                        {'REKEY_FEED_URL': 'https://example.com/feed.xml'},
                        {'REKEY_ED_PUBLIC_KEY': ''}, {'REKEY_ED_PUBLIC_KEY': 'invalid'}):
            with self.subTest(changes=changes):
                self.assertNotEqual(check(dict(env, **changes)), 0)


if __name__ == '__main__':
    unittest.main()
