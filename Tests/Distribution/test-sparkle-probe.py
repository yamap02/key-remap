#!/usr/bin/env python3
"""Exercise the real Sparkle updater using disposable keys and a loopback feed.

This downloads only an intentionally invalid local test file and never installs
an update. HTTP is used only inside the test; production requires HTTPS.
"""
import base64
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import threading
import uuid

ROOT = Path(__file__).resolve().parents[2]
FRAMEWORK = ROOT / '.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
SIGN_UPDATE = ROOT / 'build/sparkle-tools/bin/sign_update'


def command(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


class QuietHandler(SimpleHTTPRequestHandler):
    paths = []
    def do_GET(self):
        self.paths.append(self.path)
        super().do_GET()

    def log_message(self, *_):
        pass


def main():
    if not FRAMEWORK.exists() or not SIGN_UPDATE.exists():
        raise SystemExit('Resolve the Swift package and install Sparkle 2.9.6 tools in build/sparkle-tools first')
    with tempfile.TemporaryDirectory(prefix='rekey-sparkle-probe-') as directory:
        root = Path(directory)
        key_pem, key_file = root / 'key.pem', root / 'key'
        command('openssl', 'genpkey', '-algorithm', 'ED25519', '-out', str(key_pem),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        private = subprocess.check_output(['openssl', 'pkey', '-in', str(key_pem), '-outform', 'DER'])[-32:]
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(key_pem), '-pubout', '-outform', 'DER'])[-32:]
        key_file.write_bytes(base64.b64encode(private)); key_file.chmod(0o600)
        bundle_id = 'org.example.rekey.sparkle.probe.' + uuid.uuid4().hex
        cache = Path.home() / 'Library/Caches' / bundle_id
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=directory))
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            contents = root / 'Probe.app/Contents'
            (contents / 'MacOS').mkdir(parents=True); (contents / 'Frameworks').mkdir()
            binary = contents / 'MacOS/Probe'
            command('swiftc', '-parse-as-library', '-F', str(FRAMEWORK.parent), '-framework', 'Sparkle',
                    str(ROOT / 'Tests/Distribution/sparkle_probe.swift'), '-o', str(binary))
            command('ditto', str(FRAMEWORK), str(contents / 'Frameworks/Sparkle.framework'))
            command('install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(binary))
            info = dict(CFBundleExecutable='Probe', CFBundleIdentifier=bundle_id,
                        CFBundleName='Probe', CFBundlePackageType='APPL', CFBundleVersion='100',
                        CFBundleShortVersionString='1.0', LSUIElement=True,
                        SUFeedURL=f'http://127.0.0.1:{server.server_port}/appcast.xml',
                        SUPublicEDKey=base64.b64encode(public).decode(), SURequireSignedFeed=True,
                        SUVerifyUpdateBeforeExtraction=True, SUEnableAutomaticChecks=False,
                        NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
            (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
            feed = root / 'appcast.xml'

            def sign_feed(version):
                feed.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Probe</title><item><title>Test</title><sparkle:version>{version}</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><enclosure url="https://example.invalid/ReKey.zip" sparkle:edSignature="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==" length="100" type="application/octet-stream"/></item></channel></rss>''')
                command(str(SIGN_UPDATE), '--ed-key-file', str(key_file), str(feed), stdout=subprocess.DEVNULL)

            def expect(expected):
                result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
                actual = result.stdout.strip()
                if result.returncode != 0 or actual != expected:
                    raise AssertionError(f'Expected {expected}, got {actual}, exit {result.returncode}: {result.stderr}')
                print('PASS', expected)

            sign_feed(101); expect('FOUND 101')
            sign_feed(100); expect('NONE')
            sign_feed(101)
            feed.write_bytes(feed.read_bytes().replace(b'<title>Test</title>', b'<title>Altered</title>'))
            verification = subprocess.run([str(SIGN_UPDATE), '--ed-key-file', str(key_file), '--verify', str(feed)],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if verification.returncode == 0:
                raise AssertionError('Tampered feed unexpectedly verified')
            expect('ERROR 1000')  # SUAppcastParseError, including signature validation failure.

            # Keep the signed feed valid but serve different archive bytes of
            # the same length. Neither file is an installable archive.
            original, payload = root / 'original.zip', root / 'update.zip'
            original.write_bytes(b'not a valid zip - signed!!')
            payload.write_bytes(b'not a valid zip - altered!')
            assert original.stat().st_size == payload.stat().st_size
            signature = subprocess.check_output([str(SIGN_UPDATE), '--ed-key-file', str(key_file), '-p', str(original)], text=True).strip()
            feed.write_text(f'''<?xml version="1.0"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Probe</title><item><title>Test</title><sparkle:version>101</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><enclosure url="http://127.0.0.1:{server.server_port}/update.zip" sparkle:edSignature="{signature}" length="{payload.stat().st_size}" type="application/octet-stream"/></item></channel></rss>''')
            command(str(SIGN_UPDATE), '--ed-key-file', str(key_file), str(feed), stdout=subprocess.DEVNULL)
            command('xcrun', 'clang', '-fobjc-arc', '-F', str(FRAMEWORK.parent), '-framework', 'Sparkle', '-framework', 'AppKit',
                    str(ROOT / 'Tests/Distribution/sparkle_invalid_update.m'), '-o', str(binary))
            command('install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(binary))
            expect('ERROR 4005 SIGNATURE_REJECTED 1')
            if '/update.zip' not in QuietHandler.paths:
                raise AssertionError('Sparkle did not request the test update file')

            # Rebuild the informational probe before checking connection failure.
            command('swiftc', '-parse-as-library', '-F', str(FRAMEWORK.parent), '-framework', 'Sparkle',
                    str(ROOT / 'Tests/Distribution/sparkle_probe.swift'), '-o', str(binary))
            command('install_name_tool', '-add_rpath', '@executable_path/../Frameworks', str(binary))
            server.shutdown(); server.server_close(); thread.join()
            expect('ERROR 2001')  # SUDownloadError: no server is listening.
        finally:
            if thread.is_alive():
                server.shutdown(); server.server_close(); thread.join()
            # This UUID-scoped cache can only have been created by this probe.
            if cache.exists():
                shutil.rmtree(cache)


if __name__ == '__main__':
    main()
