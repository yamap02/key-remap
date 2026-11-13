#!/usr/bin/env python3
"""Prepare a signed GitHub Release draft, publish it, or verify delivery."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPO = 'yamap02/key-remap'
FEED = f'https://github.com/{REPO}/releases/latest/download/appcast.xml'
PRODUCT = 'io.github.yamap02.ReKey'
ACCOUNT = 'yamap02.key-remap.sparkle'
TOOLS = ROOT / '.build/artifacts/sparkle/Sparkle/bin'


def run(*args, capture=False):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def release_list():
    pages = json.loads(run('gh', 'api', '--paginate', '--slurp', f'repos/{REPO}/releases', capture=True))
    return [release for page in pages for release in page]


def configure(version, build):
    if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Version must be numeric, e.g. 0.1.0')
    if not re.fullmatch(r'[1-9][0-9]*', build):
        raise ValueError('Build must be a positive integer')
    for name in ('REKEY_TEAM_ID', 'REKEY_SIGNING_IDENTITY', 'REKEY_INSTALLER_IDENTITY', 'REKEY_NOTARY_PROFILE'):
        if not os.environ.get(name):
            raise ValueError(f'{name} is required; see docs/github-releases-ja.md')
    if not (TOOLS / 'generate_keys').is_file():
        raise ValueError('Run swift package resolve first (Sparkle 2.9.6 tools are required)')
    key = run(TOOLS / 'generate_keys', '--account', ACCOUNT, '-p', capture=True).strip()
    if os.environ.get('REKEY_ED_PUBLIC_KEY', key) != key:
        raise ValueError('Configured public key differs from the release Keychain key')
    os.environ.update(REKEY_RELEASE='1', REKEY_PRODUCT_ID=PRODUCT, REKEY_FEED_URL=FEED,
                      REKEY_ED_PUBLIC_KEY=key, REKEY_VERSION=version, REKEY_BUILD_NUMBER=build)
    run('/bin/zsh', '-c', 'source scripts/build-config.sh')
    repo = json.loads(run('gh', 'repo', 'view', REPO, '--json', 'visibility', capture=True))
    if repo['visibility'] != 'PUBLIC':
        raise ValueError('Release repository must be public')


def sign_verify(path, signature=None):
    args = [TOOLS / 'sign_update', '--account', ACCOUNT, '--verify', path]
    if signature:
        args.append(signature)
    run(*args)


def fetch_feed(destination):
    run('curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
        '--retry', '3', '--output', destination, FEED)
    sign_verify(destination)


def check_assets(folder, version, build, previous=None):
    archive = folder / f'ReKey-{version}.zip'
    args = [sys.executable, ROOT / 'scripts/check-appcast-assets.py', folder / 'appcast.xml',
            archive, build, f'https://github.com/{REPO}/releases/download/v{version}/{archive.name}']
    if previous:
        args.extend(['--previous', previous])
    sign_verify(folder / 'appcast.xml')
    signature = run(*args, capture=True).strip()
    sign_verify(archive, signature)


def require_tag(version):
    tag = f'v{version}'
    commit = run('git', 'rev-parse', f'{tag}^{{commit}}', capture=True).strip()
    if run('git', 'rev-parse', 'HEAD', capture=True).strip() != commit:
        raise ValueError('Check out the release tag before preparing it')
    if run('git', 'status', '--porcelain', '--untracked-files=normal', capture=True).strip():
        raise ValueError('Commit all changes before preparing a release')
    refs = run('git', 'ls-remote', f'https://github.com/{REPO}.git',
               f'refs/tags/{tag}', f'refs/tags/{tag}^{{}}', capture=True).splitlines()
    targets = {line.split()[1]: line.split()[0] for line in refs}
    if targets.get(f'refs/tags/{tag}^{{}}', targets.get(f'refs/tags/{tag}')) != commit:
        raise ValueError('Push the release tag to GitHub before preparing it')
    return commit


def previous_feed(folder, releases):
    published = [r for r in releases if not r['draft']]
    if not published:
        return None
    if not any(not r['prerelease'] for r in published):
        raise ValueError('Only prereleases exist; establish a stable feed before continuing')
    previous = folder / 'previous-appcast.xml'
    fetch_feed(previous)  # A missing or invalid feed is never treated as a first release.
    return previous


def prepare(version, build, folder):
    commit = require_tag(version)
    releases = release_list()
    if any(r['tag_name'] == f'v{version}' or r['draft'] for r in releases):
        raise ValueError('Release/tag already used or another draft exists; resolve it first')
    folder.mkdir(parents=True, exist_ok=False)
    previous = previous_feed(folder, releases)
    if previous:
        run(sys.executable, ROOT / 'scripts/check-appcast-version.py', previous, build)
    run(ROOT / 'scripts/build-app.sh')
    with tempfile.TemporaryDirectory(prefix='rekey-notary-') as tmp:
        archive = Path(tmp) / 'notary.zip'
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', ROOT / 'build/ReKey.app', archive)
        result = run('xcrun', 'notarytool', 'submit', archive, '--keychain-profile',
                     os.environ['REKEY_NOTARY_PROFILE'], '--wait', '--output-format', 'json', capture=True)
        if json.loads(result).get('status') != 'Accepted':
            raise ValueError('Notarization was not accepted; inspect notarytool log before retrying')
    run('xcrun', 'stapler', 'staple', ROOT / 'build/ReKey.app')
    run('xcrun', 'stapler', 'validate', ROOT / 'build/ReKey.app')
    run('spctl', '--assess', '--type', 'execute', '--verbose=2', ROOT / 'build/ReKey.app')
    assets = folder / 'assets'
    assets.mkdir()
    if previous:
        shutil.copy2(previous, assets / 'appcast.xml')
    archive = assets / f'ReKey-{version}.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', ROOT / 'build/ReKey.app', archive)
    run(TOOLS / 'generate_appcast', '--account', ACCOUNT, '--maximum-versions', '0',
        '--maximum-deltas', '0', '--download-url-prefix',
        f'https://github.com/{REPO}/releases/download/v{version}/', assets)
    check_assets(assets, version, build, previous)
    os.environ['REKEY_UPDATE_ARCHIVE'] = str(archive)
    package = f'ReKey-{version}.pkg'
    run(ROOT / 'scripts/build-pkg.sh', package)
    shutil.copy2(ROOT / 'build' / package, assets / package)
    names = [archive.name, package, 'appcast.xml']
    state = dict(version=version, build=build, commit=commit,
                 public_key=os.environ['REKEY_ED_PUBLIC_KEY'],
                 previous=digest(previous) if previous else None,
                 assets={name: digest(assets / name) for name in names})
    # Save recovery information before the remote mutation. Never overwrite assets.
    (folder / 'release.json').write_text(json.dumps(state, indent=2) + '\n')
    notes = folder / 'release-notes.md'
    notes.write_text((ROOT / 'docs/release-notes-template.md').read_text().replace('<版>', version))
    run('gh', 'release', 'create', f'v{version}', '--repo', REPO, '--draft', '--verify-tag',
        '--title', f'ReKey {version}', '--notes-file', notes,
        *(assets / name for name in names))
    verify_downloads(folder, state, public=False)
    print(f'Draft verified: https://github.com/{REPO}/releases/tag/v{version}')


def load_state(folder, version, build):
    state = json.loads((folder / 'release.json').read_text())
    if (state['version'], state['build'], state['public_key']) != (version, build, os.environ['REKEY_ED_PUBLIC_KEY']):
        raise ValueError('Release state does not match version, build, or signing key')
    expected = {f'ReKey-{version}.zip', f'ReKey-{version}.pkg', 'appcast.xml'}
    if set(state['assets']) != expected:
        raise ValueError('Release state has unexpected assets')
    return state


def verify_downloads(folder, state, public):
    with tempfile.TemporaryDirectory(prefix='rekey-download-') as tmp:
        target = Path(tmp)
        for name, checksum in state['assets'].items():
            if public:
                run('curl', '--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
                    '--retry', '3', '--output', target / name,
                    f'https://github.com/{REPO}/releases/download/v{state["version"]}/{name}')
            else:
                run('gh', 'release', 'download', f'v{state["version"]}', '--repo', REPO,
                    '--pattern', name, '--dir', target)
            if digest(target / name) != checksum:
                raise ValueError(f'Remote asset differs from verified local artifact: {name}')
        check_assets(target, state['version'], state['build'],
                     folder / 'previous-appcast.xml' if state['previous'] else None)
        if public:
            delivered = target / 'latest.xml'
            fetch_feed(delivered)
            if digest(delivered) != state['assets']['appcast.xml']:
                raise ValueError('Stable feed does not match this release; retry verify after cache expiry')


def publish(folder, state):
    releases = release_list()
    release = next((r for r in releases if r['tag_name'] == f'v{state["version"]}'), None)
    if not release or not release['draft'] or release['prerelease']:
        raise ValueError('Expected a non-prerelease draft')
    if require_tag(state['version']) != state['commit']:
        raise ValueError('Release tag changed after preparation')
    with tempfile.TemporaryDirectory(prefix='rekey-feed-') as tmp:
        current = previous_feed(Path(tmp), releases)
        if (digest(current) if current else None) != state['previous']:
            raise ValueError('Published feed changed since preparation; prepare a new release')
    verify_downloads(folder, state, public=False)
    run('gh', 'release', 'edit', f'v{state["version"]}', '--repo', REPO, '--draft=false', '--latest')
    verify_downloads(folder, state, public=True)
    print('Published and verified GitHub Release and stable Sparkle feed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('prepare', 'publish', 'verify'))
    parser.add_argument('version', help='display version without v')
    parser.add_argument('build', help='strictly increasing integer')
    args = parser.parse_args()
    configure(args.version, args.build)
    folder = ROOT / 'build/releases' / f'v{args.version}'
    if args.action == 'prepare':
        prepare(args.version, args.build, folder)
    else:
        state = load_state(folder, args.version, args.build)
        if args.action == 'publish':
            publish(folder, state)
        else:
            verify_downloads(folder, state, public=True)
            print('Public release and stable feed verified.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, KeyError) as error:
        sys.exit(f'Release stopped: {error}')
