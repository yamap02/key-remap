#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h:h}"
# These are test identifiers; this does not install or authorize any service.
if REKEY_PRODUCT_ID='not a bundle id' zsh -c 'source scripts/build-config.sh' >/dev/null 2>&1; then
  echo 'Invalid bundle identifier accepted' >&2; exit 1
fi
if REKEY_TEAM_ID=ABCDEFGHIJ REKEY_SIGNING_IDENTITY=- zsh -c 'source scripts/build-config.sh' >/dev/null 2>&1; then
  echo 'Ad-hoc identity accepted with Team ID' >&2; exit 1
fi
REKEY_PRODUCT_ID=org.example.rekeytest REKEY_BUILD_NUMBER=2001 REKEY_VERSION=1.2.3 scripts/build-app.sh >/dev/null
app=build/ReKey.app
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist") == org.example.rekeytest ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Library/LoginItems/ReKeyAgent.app/Contents/Info.plist") == org.example.rekeytest.agent ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist") == 2001 ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Library/LoginItems/ReKeyAgent.app/Contents/Info.plist") == 2001 ]]
/usr/bin/strings "$app/Contents/Library/HelperTools/rekey-core" | rg -q '^org[.]example[.]rekeytest$'
for notice in Resources/Licenses/*; do
  cmp "$notice" "$app/Contents/Resources/Licenses/${notice:t}"
done
cmp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Licenses/Sparkle.txt"
cmp Vendor/VirtualHID/LICENSE.md "$app/Contents/Resources/Licenses/Karabiner-DriverKit-VirtualHIDDevice.txt"
codesign --verify --deep --strict "$app"
if codesign -dv --verbose=4 "$app" 2>&1 | rg -q '^CodeDirectory .*flags=.*\(.*runtime'; then
  echo 'Ad-hoc development app must not enable Hardened Runtime library validation' >&2; exit 1
fi
print 'PASS build identity, version, signing and invalid inputs'
