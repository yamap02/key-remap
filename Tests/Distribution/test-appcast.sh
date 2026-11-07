#!/bin/zsh
set -eu
cd "${0:A:h:h:h}"
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
build/sparkle-tools/bin/generate_appcast --ed-key-file "$work/key" --download-url-prefix 'https://example.invalid/releases/' "$work/updates" > "$work/appcast.log" 2>&1
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
