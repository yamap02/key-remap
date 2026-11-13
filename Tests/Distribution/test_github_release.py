import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('github_release', Path(__file__).resolve().parents[2] / 'scripts/github-release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class GitHubReleaseTests(unittest.TestCase):
    def test_bootstrap_requires_no_published_releases(self):
        with patch.object(release, 'fetch_feed') as fetch:
            self.assertIsNone(release.previous_feed(Path('/tmp'), [{'draft': True}]))
            fetch.assert_not_called()
            with self.assertRaises(ValueError):
                release.previous_feed(Path('/tmp'), [{'draft': False, 'prerelease': True}])

    def test_missing_existing_feed_is_fatal(self):
        with patch.object(release, 'fetch_feed', side_effect=ValueError('bad signature')):
            with self.assertRaisesRegex(ValueError, 'bad signature'):
                release.previous_feed(Path('/tmp'), [{'draft': False, 'prerelease': False}])

    def test_prepare_refuses_duplicate_or_parallel_drafts_before_build(self):
        for releases in ([{'tag_name': 'v0.1.0', 'draft': False}],
                         [{'tag_name': 'v0.0.1', 'draft': True}]):
            with patch.object(release, 'require_tag', return_value='abc'), \
                 patch.object(release, 'release_list', return_value=releases), \
                 patch.object(release, 'run') as run:
                with self.assertRaises(ValueError):
                    release.prepare('0.1.0', '1', Path('/unused'))
                run.assert_not_called()

    def test_notary_rejection_never_creates_release(self):
        commands = []
        def command(*args, **kwargs):
            commands.append(args)
            if args[:3] == ('xcrun', 'notarytool', 'submit'):
                return '{"status": "Invalid"}'
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(release, 'require_tag', return_value='abc'), \
                 patch.object(release, 'release_list', return_value=[]), \
                 patch.object(release, 'run', side_effect=command):
                with self.assertRaisesRegex(ValueError, 'Notarization'):
                    with patch.dict(release.os.environ, REKEY_NOTARY_PROFILE='test-profile'):
                        release.prepare('0.1.0', '1', Path(tmp) / 'release')
        self.assertTrue(any(args[:3] == ('xcrun', 'notarytool', 'submit') for args in commands))
        self.assertFalse(any(args[0] == 'gh' for args in commands))

    def test_remote_tag_mismatch_is_rejected(self):
        outputs = iter(['abc\n', 'abc\n', '', 'def refs/tags/v0.1.0\n'])
        with patch.object(release, 'run', side_effect=lambda *a, **kw: next(outputs)):
            with self.assertRaisesRegex(ValueError, 'Push the release tag'):
                release.require_tag('0.1.0')

    def test_remote_asset_tampering_is_rejected_before_signature_checks(self):
        state = dict(version='0.1.0', build='1', previous=None,
                     assets={'appcast.xml': 'not-the-downloaded-hash'})
        def download(*args, **kwargs):
            (Path(args[-1]) / 'appcast.xml').write_bytes(b'changed')
        with patch.object(release, 'run', side_effect=download), \
             patch.object(release, 'check_assets') as check:
            with self.assertRaisesRegex(ValueError, 'differs'):
                release.verify_downloads(Path('/unused'), state, public=False)
            check.assert_not_called()

    def test_publish_refuses_stale_feed_before_remote_mutation(self):
        state = dict(version='0.1.0', build='2', commit='abc', previous='old-hash')
        releases = [dict(tag_name='v0.1.0', draft=True, prerelease=False)]
        with tempfile.TemporaryDirectory() as tmp:
            feed = Path(tmp) / 'feed.xml'
            feed.write_bytes(b'newer release')
            with patch.object(release, 'release_list', return_value=releases), \
                 patch.object(release, 'require_tag', return_value='abc'), \
                 patch.object(release, 'previous_feed', return_value=feed), \
                 patch.object(release, 'verify_downloads') as verify, \
                 patch.object(release, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'changed since'):
                    release.publish(Path(tmp), state)
                verify.assert_not_called()
                run.assert_not_called()

    def test_publish_verifies_draft_before_edit_and_public_urls_after(self):
        state = dict(version='0.1.0', build='1', commit='abc', previous=None)
        releases = [dict(tag_name='v0.1.0', draft=True, prerelease=False)]
        events = []
        with patch.object(release, 'release_list', return_value=releases), \
             patch.object(release, 'require_tag', return_value='abc'), \
             patch.object(release, 'previous_feed', return_value=None), \
             patch.object(release, 'verify_downloads', side_effect=lambda *a, **kw: events.append(kw['public'])), \
             patch.object(release, 'run', side_effect=lambda *a, **kw: events.append(a)):
            release.publish(Path('/unused'), state)
        self.assertEqual(events, [False, ('gh', 'release', 'edit', 'v0.1.0', '--repo',
                                         release.REPO, '--draft=false', '--latest'), True])

    def test_public_verification_checks_stable_feed_too(self):
        data = b'expected release'
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source'
            source.write_bytes(data)
            state = dict(version='0.1.0', build='1', previous=None,
                         assets={'appcast.xml': release.digest(source)})
            def download(*args, **kwargs):
                Path(args[args.index('--output') + 1]).write_bytes(data)
            def stale_feed(path):
                path.write_bytes(b'cached old feed')
            with patch.object(release, 'run', side_effect=download), \
                 patch.object(release, 'check_assets'), \
                 patch.object(release, 'fetch_feed', side_effect=stale_feed):
                with self.assertRaisesRegex(ValueError, 'Stable feed'):
                    release.verify_downloads(Path(tmp), state, public=True)


if __name__ == '__main__':
    unittest.main()
