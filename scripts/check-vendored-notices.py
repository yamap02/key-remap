#!/usr/bin/env python3
"""Check compiled vendored header families against documented notices.

This is an inventory check, not a legal assessment or a complete SBOM.
"""
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
INCLUDE = ROOT / 'Vendor/VirtualHID/vendor/vendor/include'
DRIVER = ROOT / 'Vendor/VirtualHID/include'
NOTICES = {
    'asio': 'Boost-Software-License-1.0.txt',
    'asio.hpp': 'Boost-Software-License-1.0.txt',
    'gsl': 'Microsoft-GSL.txt',
    'nlohmann': 'nlohmann-json.txt',
    'nod': 'nod.txt',
    'pqrs': 'Boost-Software-License-1.0.txt',
    'type_safe': 'type_safe.txt',
}


def inspect(paths):
    families = set()
    driver_used = False
    for name in paths:
        path = Path(name)
        path = (ROOT / path).resolve() if not path.is_absolute() else path.resolve()
        if path.is_relative_to(INCLUDE):
            family = path.relative_to(INCLUDE).parts[0]
            if family not in NOTICES:
                raise ValueError(f'new vendored header family needs license review: {family}')
            families.add(family)
        elif path.is_relative_to(DRIVER):
            driver_used = True
        elif path.is_relative_to(ROOT / 'Vendor'):
            raise ValueError(f'unclassified vendored dependency: {path.relative_to(ROOT)}')
    for family in families:
        if not (ROOT / 'Resources/Licenses' / NOTICES[family]).is_file():
            raise ValueError(f'license notice missing for {family}: {NOTICES[family]}')
    if driver_used and not (ROOT / 'Vendor/VirtualHID/LICENSE.md').is_file():
        raise ValueError('VirtualHID license is missing')
    return families, driver_used


def main():
    all_paths = []
    for source in ('Core/core.mm', 'Core/bench.cpp', 'CoreValidation/validate.cpp'):
        command = ['xcrun', 'clang++', '-std=c++23', '-M', '-ICore', '-ICoreValidation/include',
                   '-isystem', str(INCLUDE), '-isystem', str(DRIVER)]
        if source.endswith('.mm'):
            command.append('-fobjc-arc')
        result = subprocess.run(command + [source], cwd=ROOT, check=True, capture_output=True, text=True)
        dependency_list = result.stdout.replace('\\\n', ' ').split(':', 1)[1]
        all_paths.extend(shlex.split(dependency_list))
    families, driver_used = inspect(all_paths)
    if not families or not driver_used:
        raise ValueError('expected vendored dependencies were not detected')
    print('Vendored header families with notices: ' + ', '.join(sorted(families)) + '; VirtualHID client')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, IndexError, subprocess.CalledProcessError) as error:
        sys.exit(f'Vendored notice inventory failed: {error}')
