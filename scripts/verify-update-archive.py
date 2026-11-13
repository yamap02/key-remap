#!/usr/bin/env python3
"""Compare a ditto update zip with the app selected for the initial pkg."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(chunk)
    return result.digest()


def verify(app, archive):
    expected = {}
    for root, dirs, files in os.walk(app, followlinks=False):
        for name in dirs + files:
            path = Path(root) / name
            relative = path.relative_to(app).as_posix()
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                expected[relative] = ('link', os.fsencode(os.readlink(path)))
            elif stat.S_ISREG(mode):
                with path.open('rb') as stream:
                    expected[relative] = ('file', stat.S_IMODE(mode), digest(stream))
            elif not stat.S_ISDIR(mode):
                raise ValueError(f'unsupported app file: {relative}')
    if not expected:
        raise ValueError('app is empty')
    actual = {}
    with zipfile.ZipFile(archive) as zipped:
        for item in zipped.infolist():
            name = item.filename
            # Inspect metadata paths too, before any caller extracts the zip.
            # PurePosixPath normalizes dot components, so check the raw name.
            components = name.rstrip('/').split('/')
            if name.startswith('/') or any(part in ('', '.', '..') for part in components):
                raise ValueError(f'unsafe archive entry: {name}')
            parts = PurePosixPath(name).parts
            if name.startswith('__MACOSX/') or name == '__MACOSX':
                continue
            if not parts or parts[0] != app.name:
                raise ValueError(f'unexpected archive entry: {name}')
            if item.is_dir():
                continue
            relative = '/'.join(parts[1:])
            if not relative or relative in actual:
                raise ValueError(f'duplicate or invalid archive entry: {name}')
            mode = item.external_attr >> 16
            with zipped.open(item) as stream:
                if stat.S_ISLNK(mode):
                    actual[relative] = ('link', stream.read())
                elif stat.S_ISREG(mode):
                    actual[relative] = ('file', stat.S_IMODE(mode), digest(stream))
                else:
                    raise ValueError(f'unsupported archive entry: {name}')
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        changed = sorted(k for k in expected.keys() & actual.keys() if expected[k] != actual[k])
        raise ValueError(f'archive differs from app (missing={missing[:5]}, extra={extra[:5]}, changed={changed[:5]})')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]))
    except (IndexError, OSError, ValueError, zipfile.BadZipFile) as error:
        sys.exit(f'Update archive check failed: {error}')
    print('Update archive contents match the app selected for the installer.')
