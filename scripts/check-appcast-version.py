#!/usr/bin/env python3
"""Check the next integer build against every item in a trusted appcast.

The caller must authenticate the feed before invoking this tool. Human-readable
versions are intentionally not used as the Sparkle update ordering key.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def check(feed, candidate):
    if not re.fullmatch(r'[1-9][0-9]*', candidate):
        raise ValueError('candidate build must be a positive integer')
    root = ET.parse(feed).getroot()
    items = root.findall('./channel/item')
    if not items:
        raise ValueError('feed has no releases; use the explicit bootstrap procedure')
    versions = []
    for item in items:
        value = item.findtext(SPARKLE + 'version')
        enclosure = item.find('enclosure')
        if value is None and enclosure is not None:
            value = enclosure.get(SPARKLE + 'version')
        if value is None or not re.fullmatch(r'[1-9][0-9]*', value):
            raise ValueError('feed contains a missing or non-integer build version')
        versions.append(int(value))
    if int(candidate) <= max(versions):
        raise ValueError(f'build {candidate} must be greater than published build {max(versions)}')
    return max(versions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('feed')
    parser.add_argument('build')
    args = parser.parse_args()
    try:
        latest = check(args.feed, args.build)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f'Version check failed: {error}', file=sys.stderr)
        return 1
    print(f'Build {args.build} follows published build {latest}.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
