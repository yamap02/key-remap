#!/usr/bin/env python3
"""Reject ad-hoc, wrong-team or non-Developer-ID signatures in a release app."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def validate_description(description, expected_team):
    team = re.search(r'^TeamIdentifier=(.+)$', description, re.MULTILINE)
    authorities = re.findall(r'^Authority=(.+)$', description, re.MULTILINE)
    flags = re.search(r'^CodeDirectory .*flags=0x[0-9a-f]+\(([^)]*)\)', description, re.MULTILINE)
    if not team or team.group(1) != expected_team:
        raise ValueError('Team ID missing or incorrect')
    if not authorities or not authorities[0].startswith('Developer ID Application: '):
        raise ValueError('Developer ID Application leaf certificate required')
    if not flags or 'runtime' not in flags.group(1).split(',') or 'adhoc' in flags.group(1).split(','):
        raise ValueError('Hardened Runtime and a non-ad-hoc signature are required')
    if not re.search(r'^Timestamp=.+$', description, re.MULTILINE):
        raise ValueError('A secure signing timestamp is required')


def verify(app, team):
    env = dict(os.environ, LC_ALL='C')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True, env=env)
    framework = app / 'Contents/Frameworks/Sparkle.framework'
    version = framework / 'Versions/B'
    targets = [
        app, app / 'Contents/Library/LoginItems/ReKeyAgent.app',
        app / 'Contents/Library/HelperTools/rekey-core',
        app / 'Contents/Library/HelperTools/rekey-bench',
        framework, version / 'Autoupdate', version / 'Updater.app',
        version / 'XPCServices/Installer.xpc', version / 'XPCServices/Downloader.xpc',
    ]
    requirement = ('=anchor apple generic and '
                   'certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
                   'certificate leaf[field.1.2.840.113635.100.6.1.13] exists and '
                   f'certificate leaf[subject.OU] = "{team}"')
    for target in targets:
        # Check the Apple certificate chain and Team ID cryptographically;
        # a certificate's human-readable common name alone is not proof.
        subprocess.run(['codesign', '--verify', '--strict', '-R', requirement, str(target)],
                       check=True, env=env, capture_output=True)
        result = subprocess.run(['codesign', '-dv', '--verbose=4', str(target)],
                                check=True, text=True, capture_output=True, env=env)
        try:
            validate_description(result.stdout + result.stderr, team)
        except ValueError as error:
            raise ValueError(f'{target}: {error}') from error


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('team')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team):
        parser.error('team must be a 10-character Team ID')
    try:
        verify(args.app, args.team)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Release signature verification failed: {error}', file=sys.stderr)
        return 1
    print('Release code signatures and signing team verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
