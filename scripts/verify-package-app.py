#!/usr/bin/env python3
"""Check that the app being packaged matches the requested release settings."""
import os
from pathlib import Path
import plistlib
import sys


def validate(app, env):
    product = env['REKEY_PRODUCT_ID']
    common = {'ReKeyProductIdentifier': product,
              'CFBundleShortVersionString': env['REKEY_VERSION'],
              'CFBundleVersion': env['REKEY_BUILD_NUMBER']}
    app_expected = dict(common, CFBundleIdentifier=product,
                        SUFeedURL=env['REKEY_FEED_URL'],
                        SUPublicEDKey=env['REKEY_ED_PUBLIC_KEY'],
                        SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True,
                        SUAllowsAutomaticUpdates=False)
    agent_expected = dict(common, CFBundleIdentifier=product + '.agent')
    for path, expected in ((app / 'Contents/Info.plist', app_expected),
                           (app / 'Contents/Library/LoginItems/ReKeyAgent.app/Contents/Info.plist', agent_expected)):
        with path.open('rb') as stream:
            data = plistlib.load(stream)
        for key, value in expected.items():
            if key not in data or type(data[key]) is not type(value) or data[key] != value:
                raise ValueError(f'{path}: {key} does not match release settings')


if __name__ == '__main__':
    try:
        validate(Path(sys.argv[1]), os.environ)
    except (IndexError, KeyError, OSError, ValueError, plistlib.InvalidFileException) as error:
        sys.exit(f'Cannot package release app: {error}')
