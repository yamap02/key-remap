#!/usr/bin/env python3
"""Compare an authenticated appcast with the release archive and prior feed.

Authenticate both feeds and the archive's EdDSA signature separately before
publishing. This check validates metadata, not cryptographic signatures.
"""
import argparse
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def releases(path):
    items = ET.parse(path).getroot().findall('./channel/item')
    if not items:
        raise ValueError('appcast has no releases')
    result = {}
    for item in items:
        enclosure = item.find('enclosure')
        if enclosure is None or len(item.findall('enclosure')) != 1:
            raise ValueError('each release must have exactly one enclosure')
        version = item.findtext(NS + 'version')
        legacy = enclosure.get(NS + 'version')
        if version is None:
            version = legacy
        elif legacy is not None and legacy != version:
            raise ValueError('conflicting build versions')
        if not version or not re.fullmatch(r'[1-9][0-9]*', version) or version in result:
            raise ValueError('missing, invalid, or duplicate build')
        url = enclosure.get('url', '')
        parsed = urlsplit(url)
        length = enclosure.get('length', '')
        signature = enclosure.get(NS + 'edSignature', '')
        if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
                or parsed.fragment or not re.fullmatch(r'[1-9][0-9]*', length) or not signature):
            raise ValueError(f'build {version} has invalid enclosure metadata')
        result[version] = (url, length, signature)
    return result


def check(feed, archive, build, expected_url, previous=None):
    current = releases(feed)
    if build not in current:
        raise ValueError('expected build is absent from appcast')
    url, length, signature = current[build]
    if url != expected_url or int(length) != archive.stat().st_size:
        raise ValueError('new archive URL or size does not match appcast')
    if previous is not None:
        old = releases(previous)
        if int(build) <= max(map(int, old)):
            raise ValueError('new build must be newer than every previous build')
        if set(current) != set(old) | {build}:
            raise ValueError('appcast lost or added unexpected release history')
        for version, enclosure in old.items():
            if current[version] != enclosure:
                raise ValueError(f'published enclosure changed for build {version}')
    elif set(current) != {build}:
        raise ValueError('bootstrap appcast must contain exactly the first build')
    return signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('feed', type=Path)
    parser.add_argument('archive', type=Path)
    parser.add_argument('build')
    parser.add_argument('url', help='exact immutable HTTPS URL for this archive')
    parser.add_argument('--previous', type=Path, help='previous authenticated feed; omit only for first release')
    args = parser.parse_args()
    try:
        signature = check(args.feed, args.archive, args.build, args.url, args.previous)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f'Appcast asset check failed: {error}', file=sys.stderr)
        return 1
    # The signature is public and is passed to sign_update --verify by caller.
    print(signature)
    return 0


if __name__ == '__main__':
    sys.exit(main())
