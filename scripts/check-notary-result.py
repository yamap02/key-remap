#!/usr/bin/env python3
"""Require a completed, accepted notarytool JSON response."""
import json
import sys


def accepted(value):
    return isinstance(value, dict) and value.get('status') == 'Accepted'


def main():
    try:
        with open(sys.argv[1], encoding='utf-8') as source:
            value = json.load(source)
    except (IndexError, OSError, ValueError) as error:
        print(f'Could not read notary result: {error}', file=sys.stderr)
        return 1
    if not accepted(value):
        print('Notarization was not accepted; inspect the submission with notarytool before retrying', file=sys.stderr)
        return 1
    print('Notarization accepted.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
