#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/build-config.sh
scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ReKey.app/Contents/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/ReKey.app/Contents/Info.plist)"
package_filename="${1:-ReKey-${version}.pkg}"
if [[ "$package_filename" == */* || "$package_filename" != *.pkg ]]; then echo "Pass a .pkg filename without directories" >&2; exit 64; fi
package_output="build/$package_filename"
stage=$(mktemp -d "${TMPDIR:-/tmp}/rekey-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/Applications" "$stage/scripts"
ditto --noextattr --noqtn --norsrc build/ReKey.app "$stage/root/Applications/ReKey.app"
cat > "$stage/scripts/preinstall" <<'SCRIPT'
#!/bin/sh
set -eu
# Stop the old capture process before removing its output helper. launchd's
# Background Items registration is refreshed through SMAppService by the UI.
/bin/launchctl bootout system/jp.example.rekey.core 2>/dev/null || true
/bin/launchctl bootout system/jp.example.rekey.vhid 2>/dev/null || true
exit 0
SCRIPT
chmod 755 "$stage/scripts/preinstall"
cat > "$stage/scripts/postinstall" <<'SCRIPT'
#!/bin/sh
set -eu
chown -R root:wheel /Applications/ReKey.app
chmod -R go-w /Applications/ReKey.app
exit 0
SCRIPT
chmod 755 "$stage/scripts/postinstall"
pkgbuild --analyze --root "$stage/root" "$stage/components.plist"
/usr/bin/python3 - "$stage/components.plist" <<'PYTHON'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as stream:
    components = plistlib.load(stream)
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleIsVersionChecked'] = False
with open(path, 'wb') as stream:
    plistlib.dump(components, stream)
PYTHON
args=(--component-plist "$stage/components.plist" --root "$stage/root" --scripts "$stage/scripts" --identifier "${REKEY_PRODUCT_ID}.pkg" --version "$build_number" --install-location / --ownership recommended)
if [[ -n "${REKEY_INSTALLER_IDENTITY:-}" ]]; then args+=(--sign "$REKEY_INSTALLER_IDENTITY"); fi
pkgbuild "${args[@]}" "$package_output"
if [[ -n "${REKEY_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$package_output" --keychain-profile "$REKEY_NOTARY_PROFILE" --wait
  xcrun stapler staple "$package_output"
else
  echo "Development package: not notarized. Distribution requires Developer ID signing and notarization."
fi
