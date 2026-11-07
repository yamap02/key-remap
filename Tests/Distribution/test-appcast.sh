#!/bin/zsh
set -eu
cd "${0:A:h:h:h}"
# Fixtures must never inherit real distribution signing or notary settings.
unset REKEY_SIGNING_IDENTITY REKEY_TEAM_ID REKEY_INSTALLER_IDENTITY REKEY_NOTARY_PROFILE
unset REKEY_PRODUCT_ID REKEY_FEED_URL REKEY_ED_PUBLIC_KEY
export REKEY_RELEASE=0
[[ -x build/sparkle-tools/bin/generate_appcast ]] || { echo "Install Sparkle 2.9.6 release tools in build/sparkle-tools first" >&2; exit 1; }
work=$(mktemp -d /tmp/rekey-sparkle-test.XXXXXX)
trap 'rm -rf "$work"' EXIT
umask 077
openssl genpkey -algorithm ED25519 -out "$work/key.pem" 2>/dev/null
openssl pkey -in "$work/key.pem" -outform DER -out "$work/key.der" 2>/dev/null
openssl pkey -in "$work/key.pem" -pubout -outform DER -out "$work/pub.der" 2>/dev/null
python3 - "$work" <<'PY'
import base64, pathlib, sys
p=pathlib.Path(sys.argv[1])
(p/'key').write_bytes(base64.b64encode((p/'key.der').read_bytes()[-32:]))
(p/'pub').write_bytes(base64.b64encode((p/'pub.der').read_bytes()[-32:]))
PY
export REKEY_FEED_URL='https://example.invalid/appcast.xml'
export REKEY_ED_PUBLIC_KEY="$(cat "$work/pub")"
export REKEY_BUILD_NUMBER=1001 REKEY_VERSION=0.1.1
scripts/build-app.sh > "$work/build.log" 2>&1
mkdir "$work/updates"
ditto -c -k --sequesterRsrc --keepParent build/ReKey.app "$work/updates/ReKey-0.1.1.zip"
build/sparkle-tools/bin/generate_appcast --ed-key-file "$work/key" --maximum-versions 0 --maximum-deltas 0 --download-url-prefix 'https://github.com/example/repo/releases/download/v0.1.1/' "$work/updates" > "$work/appcast.log" 2>&1
build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/updates/appcast.xml"
python3 - "$work/updates/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as E
root=E.parse(sys.argv[1]).getroot()
ns='{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item=root.find('./channel/item')
assert item is not None and item.findtext(ns+'version') == '1001'
e=item.find('enclosure'); assert e is not None and e.get(ns+'edSignature') and e.get('url','').startswith('https://')
print('PASS signed appcast with expected build and HTTPS enclosure')
PY

# Reuse only the signed feed, as a release operator would; do not copy the old
# archive into the new release folder. Previous asset URLs must remain fixed.
mkdir "$work/next"
cp "$work/updates/appcast.xml" "$work/next/appcast.xml"
build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/next/appcast.xml"
python3 scripts/check-appcast-version.py "$work/next/appcast.xml" 1002
if python3 scripts/check-appcast-version.py "$work/next/appcast.xml" 1001 >/dev/null 2>&1; then
  echo "Duplicate build unexpectedly accepted" >&2; exit 1
fi
export REKEY_BUILD_NUMBER=1002 REKEY_VERSION=0.1.2
scripts/build-app.sh > "$work/build-next.log" 2>&1
ditto -c -k --sequesterRsrc --keepParent build/ReKey.app "$work/next/ReKey-0.1.2.zip"
build/sparkle-tools/bin/generate_appcast --ed-key-file "$work/key" --maximum-versions 0 --maximum-deltas 0 --download-url-prefix 'https://github.com/example/repo/releases/download/v0.1.2/' "$work/next" > "$work/appcast-next.log" 2>&1
build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/next/appcast.xml"
python3 - "$work/next/appcast.xml" "$work/updates/appcast.xml" <<'PYTHON'
import sys, xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).getroot().findall('./channel/item')
previous = ET.parse(sys.argv[2]).getroot().find('./channel/item/enclosure')
urls = {item.findtext(ns+'version'): item.find('enclosure').get('url') for item in items}
expected = {
    '1001': 'https://github.com/example/repo/releases/download/v0.1.1/ReKey-0.1.1.zip',
    '1002': 'https://github.com/example/repo/releases/download/v0.1.2/ReKey-0.1.2.zip',
}
assert urls == expected, (urls, expected)
assert [item.findtext(ns+'version') for item in items] == ['1002', '1001']
assert items[1].find('enclosure').get(ns+'edSignature') == previous.get(ns+'edSignature')
print('PASS successive signed feeds preserve old release URL, signature and ordering')
PYTHON
next_sig=$(python3 - "$work/next/appcast.xml" <<'PYTHON'
import sys, xml.etree.ElementTree as ET
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(sys.argv[1]).getroot().findall('./channel/item')
print(next(item.find('enclosure').get(ns+'edSignature') for item in items if item.findtext(ns+'version') == '1002'))
PYTHON
)
build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/next/ReKey-0.1.2.zip" "$next_sig" > /dev/null

cp "$work/updates/appcast.xml" "$work/tampered.xml"
python3 - "$work/tampered.xml" <<'PYTHON'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); data = p.read_bytes()
p.write_bytes(data.replace(b'1001', b'1002', 1))
PYTHON
if build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/tampered.xml" > /dev/null 2>&1; then
  echo "Tampered feed unexpectedly verified" >&2; exit 1
fi
sig=$(python3 - "$work/updates/appcast.xml" <<'PYTHON'
import sys, xml.etree.ElementTree as E
e = E.parse(sys.argv[1]).find('./channel/item/enclosure')
print(e.get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PYTHON
)
build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/updates/ReKey-0.1.1.zip" "$sig" > /dev/null
printf x >> "$work/updates/ReKey-0.1.1.zip"
if build/sparkle-tools/bin/sign_update --ed-key-file "$work/key" --verify "$work/updates/ReKey-0.1.1.zip" "$sig" > /dev/null 2>&1; then
  echo "Tampered archive unexpectedly verified" >&2; exit 1
fi
print 'PASS tampered feed and update rejected'
