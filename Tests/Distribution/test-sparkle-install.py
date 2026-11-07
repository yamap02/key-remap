#!/usr/bin/env python3
"""Update an isolated, user-owned test app; never touches installed ReKey.

The fixture uses ad-hoc signatures, a disposable EdDSA key and loopback HTTP.
It tests recovery against simulated service state, not real launchd services,
root ownership, Developer ID or notarization.
"""
import base64
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
FRAMEWORK = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
SIGN_UPDATE = ROOT / 'build/sparkle-tools/bin/sign_update'


class QuietHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/update.zip':
            mode = getattr(self.server, 'fail_download', '')
            if mode == 'not-found':
                self.send_error(404)
                return
            if mode == 'disconnect':
                payload = Path(self.translate_path(self.path))
                self.send_response(200)
                self.send_header('Content-Length', str(payload.stat().st_size))
                self.end_headers()
                with payload.open('rb') as stream:
                    chunk = stream.read(16384)
                assert len(chunk) == 16384 and payload.stat().st_size > len(chunk)
                self.wfile.write(chunk)
                self.wfile.flush()
                self.server.truncated_responses += 1
                self.connection.shutdown(socket.SHUT_RDWR)
                self.close_connection = True
                return
        super().do_GET()

    def log_message(self, *_):
        pass


def command(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def main():
    if not FRAMEWORK.exists() or not SIGN_UPDATE.exists():
        raise SystemExit('Resolve Sparkle and install its 2.9.6 tools in build/sparkle-tools first')
    with tempfile.TemporaryDirectory(prefix='rekey-install-fixture-') as directory:
        root = Path(directory)
        state = root / 'state'; state.mkdir()
        config = state / 'config'; config.write_text('personal-setting')
        (state / 'service-core').write_text('enabled')
        (state / 'service-agent').write_text('notRegistered')
        pem, key = root / 'key.pem', root / 'key'
        command('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(pem),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        private = subprocess.check_output(['openssl', 'pkey', '-in', str(pem), '-outform', 'DER'])[-32:]
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(pem), '-pubout', '-outform', 'DER'])[-32:]
        key.write_bytes(base64.b64encode(private)); key.chmod(0o600)
        binary = root / 'fixture-binary'
        command('xcrun', 'clang', '-fobjc-arc', '-F', str(FRAMEWORK.parent), '-framework', 'Sparkle', '-framework', 'AppKit',
                str(ROOT / 'Tests/Distribution/sparkle_install_probe.m'), '-o', str(binary))
        helper = root / 'recovery-fixture'
        command('swiftc', '-parse-as-library', str(ROOT / 'Sources/ReKeyApp/UpdateServiceRecovery.swift'),
                str(ROOT / 'Tests/Distribution/sparkle_recovery_fixture.swift'), '-o', str(helper))
        bundle_id = 'org.example.rekey.installfixture.' + uuid.uuid4().hex
        cache = Path.home() / 'Library/Caches' / bundle_id
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=directory))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        process = None
        try:
            for name, version in [('cancel', '100'), ('invalid', '100'), ('network', '100'), ('old', '100'), ('new', '101')]:
                app = root / name / 'Fixture.app'
                contents = app / 'Contents'
                (contents / 'MacOS').mkdir(parents=True); (contents / 'Frameworks').mkdir()
                shutil.copy2(binary, contents / 'MacOS/Fixture')
                framework = contents / 'Frameworks/Sparkle.framework'
                command('ditto', str(FRAMEWORK), str(framework))
                command('install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(contents / 'MacOS/Fixture'))
                fixture_id = bundle_id + '.' + name if name in ('cancel', 'invalid', 'network') else bundle_id
                info = dict(CFBundleExecutable='Fixture', CFBundleIdentifier=fixture_id, CFBundleName='Fixture',
                            CFBundlePackageType='APPL', CFBundleVersion=version,
                            CFBundleShortVersionString='1.0' if version == '100' else '1.1', LSUIElement=True,
                            FixtureState=str(state), FixtureHelper=str(helper), FixtureSuite=fixture_id, FixtureMode=name,
                            SUFeedURL=f'http://127.0.0.1:{server.server_port}/appcast.xml',
                            SUPublicEDKey=base64.b64encode(public).decode(), SURequireSignedFeed=True,
                            SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=False, SUAllowsAutomaticUpdates=False,
                            NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
                (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
                base = framework / 'Versions/B'
                for target in [base / 'XPCServices/Installer.xpc', base / 'XPCServices/Downloader.xpc',
                               base / 'Autoupdate', base / 'Updater.app', framework, app]:
                    command('codesign', '--force', '--sign', '-', str(target), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                command('codesign', '--verify', '--deep', '--strict', str(app))
            archive = root / 'update.zip'
            command('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(root / 'new/Fixture.app'), str(archive))
            signature = subprocess.check_output([str(SIGN_UPDATE), '--ed-key-file', str(key), '-p', str(archive)], text=True).strip()
            feed = root / 'appcast.xml'
            feed.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Probe</title><item><title>Test</title><sparkle:version>101</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><enclosure url="http://127.0.0.1:{server.server_port}/update.zip" sparkle:edSignature="{signature}" length="{archive.stat().st_size}" type="application/octet-stream"/></item></channel></rss>''')
            command(str(SIGN_UPDATE), '--ed-key-file', str(key), str(feed), stdout=subprocess.DEVNULL)
            cancelled = subprocess.run([str(root / 'cancel/Fixture.app/Contents/MacOS/Fixture')],
                                       capture_output=True, text=True, timeout=30)
            if (cancelled.returncode != 0 or not (state / 'cancelled').exists() or
                (state / 'service-core').read_text() != 'enabled' or
                (state / 'service-agent').read_text() != 'notRegistered' or
                (state / 'actions').read_text().splitlines() != ['stop-core', 'start-core'] or
                plistlib.loads((root / 'cancel/Fixture.app/Contents/Info.plist').read_bytes())['CFBundleVersion'] != '100'):
                raise AssertionError(f'Cancellation recovery failed: {cancelled.stderr[-3000:]}')
            print('PASS cancelled Sparkle download restored simulated service without replacing app')
            (state / 'actions').unlink()
            original = archive.read_bytes()
            altered = bytearray(original); altered[len(altered) // 2] ^= 1
            archive.write_bytes(altered)
            invalid = subprocess.run([str(root / 'invalid/Fixture.app/Contents/MacOS/Fixture')],
                                     capture_output=True, text=True, timeout=30)
            archive.write_bytes(original)
            if (invalid.returncode != 0 or not (state / 'invalid-recovered').exists() or
                (state / 'service-core').read_text() != 'enabled' or
                (state / 'service-agent').read_text() != 'notRegistered' or
                (state / 'actions').read_text().splitlines() != ['stop-core', 'start-core'] or
                config.read_text() != 'personal-setting' or
                plistlib.loads((root / 'invalid/Fixture.app/Contents/Info.plist').read_bytes())['CFBundleVersion'] != '100'):
                raise AssertionError(f'Invalid signature recovery failed: {invalid.stderr[-3000:]}')
            print('PASS invalid update signature restored simulated service and preserved app and settings')
            (state / 'actions').unlink()
            server.fail_download = 'not-found'
            network = subprocess.run([str(root / 'network/Fixture.app/Contents/MacOS/Fixture')],
                                     capture_output=True, text=True, timeout=30)
            server.fail_download = ''
            if (network.returncode != 0 or not (state / 'network-recovered').exists() or
                (state / 'service-core').read_text() != 'enabled' or
                (state / 'service-agent').read_text() != 'notRegistered' or
                (state / 'actions').read_text().splitlines() != ['stop-core', 'start-core'] or
                config.read_text() != 'personal-setting' or
                plistlib.loads((root / 'network/Fixture.app/Contents/Info.plist').read_bytes())['CFBundleVersion'] != '100'):
                raise AssertionError(f'Download failure recovery failed: {network.stderr[-3000:]}')
            print('PASS HTTP download failure restored simulated service and preserved app and settings')
            (state / 'actions').unlink()
            (state / 'network-recovered').unlink()
            command(str(helper), str(state), bundle_id + '.network', 'cleanup')
            server.truncated_responses = 0
            server.fail_download = 'disconnect'
            interrupted = subprocess.run([str(root / 'network/Fixture.app/Contents/MacOS/Fixture')],
                                         capture_output=True, text=True, timeout=30)
            server.fail_download = ''
            if (interrupted.returncode != 0 or server.truncated_responses < 1 or
                not (state / 'network-recovered').exists() or
                (state / 'service-core').read_text() != 'enabled' or
                (state / 'service-agent').read_text() != 'notRegistered' or
                (state / 'actions').read_text().splitlines() != ['stop-core', 'start-core'] or
                config.read_text() != 'personal-setting' or
                plistlib.loads((root / 'network/Fixture.app/Contents/Info.plist').read_bytes())['CFBundleVersion'] != '100'):
                raise AssertionError(f'Interrupted download recovery failed: {interrupted.stderr[-3000:]}')
            print('PASS interrupted download restored simulated service and preserved app and settings')
            (state / 'actions').unlink()
            with (root / 'stderr').open('w+') as stderr:
                process = subprocess.Popen([str(root / 'old/Fixture.app/Contents/MacOS/Fixture')],
                                           stdout=subprocess.DEVNULL, stderr=stderr)
                deadline = time.monotonic() + 45
                marker, error = state / 'new-version', state / 'error'
                while time.monotonic() < deadline and not marker.exists() and not error.exists():
                    if process.poll() not in (None, 0):
                        break
                    time.sleep(0.2)
                if not marker.exists() or error.exists():
                    stderr.flush(); stderr.seek(0)
                    details = error.read_text() if error.exists() else f'process status: {process.poll()}'
                    raise AssertionError(f'Isolated update failed: {details}; stderr: {stderr.read()[-3000:]}')
                if marker.read_text() != 'personal-setting' or config.read_text() != 'personal-setting':
                    raise AssertionError('The fixture configuration was not retained')
                if ((state / 'service-core').read_text() != 'enabled' or
                    (state / 'service-agent').read_text() != 'notRegistered' or
                    (state / 'actions').read_text().splitlines() != ['stop-core', 'start-core']):
                    raise AssertionError('Recovery did not restore only the previously enabled service')
                installed = root / 'old/Fixture.app/Contents/Info.plist'
                if plistlib.loads(installed.read_bytes()).get('CFBundleVersion') != '101':
                    raise AssertionError('The fixture app was not replaced with build 101')
                command('codesign', '--verify', '--deep', '--strict', str(root / 'old/Fixture.app'))
                print('PASS isolated app updated 100 -> 101, retained configuration, and restored simulated service')
        finally:
            if process is not None and process.poll() is None:
                process.terminate(); process.wait(timeout=5)
            server.shutdown(); server.server_close(); thread.join()
            if cache.exists():
                shutil.rmtree(cache)
            cancel_cache = Path.home() / 'Library/Caches' / (bundle_id + '.cancel')
            if cancel_cache.exists():
                shutil.rmtree(cancel_cache)
            invalid_cache = Path.home() / 'Library/Caches' / (bundle_id + '.invalid')
            if invalid_cache.exists():
                shutil.rmtree(invalid_cache)
            network_cache = Path.home() / 'Library/Caches' / (bundle_id + '.network')
            if network_cache.exists():
                shutil.rmtree(network_cache)
            command(str(helper), str(state), bundle_id, 'cleanup')
            command(str(helper), str(state), bundle_id + '.cancel', 'cleanup')
            command(str(helper), str(state), bundle_id + '.invalid', 'cleanup')
            command(str(helper), str(state), bundle_id + '.network', 'cleanup')


if __name__ == '__main__':
    main()
