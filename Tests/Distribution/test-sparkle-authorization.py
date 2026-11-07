#!/usr/bin/env python3
"""Probe Sparkle 2.9.6 authorization decisions without replacing any app.

The optional --root-bundle must name an existing root-owned, non-writable app.
This calls a private Sparkle API only as a version-pinned diagnostic; production
ReKey never relies on that private API or invokes administrator authorization.
"""
import argparse
import os
from pathlib import Path
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FRAMEWORK_DIR = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root-bundle', type=Path)
    args = parser.parse_args()
    if not (FRAMEWORK_DIR / 'Sparkle.framework').is_dir():
        parser.error('Resolve the pinned Sparkle Swift package first')
    if args.root_bundle is not None:
        details = args.root_bundle.stat()
        if not stat.S_ISDIR(details.st_mode) or details.st_uid != 0 or os.access(args.root_bundle, os.W_OK):
            parser.error('root-bundle must be an existing root-owned directory that this user cannot write')
    with tempfile.TemporaryDirectory(prefix='rekey-authorization-test-') as directory:
        root = Path(directory)
        binary = root / 'authorization-probe'
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-F', str(FRAMEWORK_DIR), '-framework', 'Sparkle',
                        '-framework', 'Foundation', str(ROOT / 'Tests/Distribution/sparkle_authorization_probe.m'),
                        '-o', str(binary)], check=True)
        env = dict(os.environ, DYLD_FRAMEWORK_PATH=str(FRAMEWORK_DIR))
        def probe(path):
            return subprocess.check_output([str(binary), str(path)], env=env, text=True).strip()
        owned = root / 'Fixture.app'; owned.mkdir()
        if probe(owned) != 'authorization-not-required':
            raise AssertionError('A user-owned writable fixture unexpectedly required authorization')
        print('PASS user-owned writable fixture: no authorization required')
        if args.root_bundle is not None:
            if probe(args.root_bundle) != 'authorization-required':
                raise AssertionError('The root-owned non-writable app did not require authorization')
            print('PASS root-owned non-writable bundle: authorization required')


if __name__ == '__main__':
    main()
