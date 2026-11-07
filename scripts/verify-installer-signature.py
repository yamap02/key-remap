#!/usr/bin/env python3
"""Check a flat package for a trusted Developer ID Installer signature."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def validate_description(description, expected_team):
    if 'Status: signed by a developer certificate issued by Apple for distribution' not in description:
        raise ValueError('A trusted Apple distribution signature is required')
    if 'Signed with a trusted timestamp' not in description:
        raise ValueError('A trusted signing timestamp is required')
    leaf = re.search(r'^\s*1\. Developer ID Installer: .+ \(([A-Z0-9]{10})\)\s*$', description, re.MULTILINE)
    if not leaf or leaf.group(1) != expected_team:
        raise ValueError('Developer ID Installer leaf certificate or team does not match')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('team')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Z0-9]{10}', args.team):
        parser.error('team must be a 10-character Team ID')
    try:
        env = dict(os.environ, LC_ALL='C')
        result = subprocess.run(['pkgutil', '--check-signature', str(args.package)],
                                check=True, text=True, capture_output=True, env=env)
        validate_description(result.stdout + result.stderr, args.team)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Installer signature verification failed: {error}', file=sys.stderr)
        return 1
    print('Installer signature, timestamp and signing team verified.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
