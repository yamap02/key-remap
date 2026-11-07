#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/build-config.sh
if [[ "$REKEY_RELEASE" == 1 && ( -z "${REKEY_INSTALLER_IDENTITY:-}" || -z "${REKEY_NOTARY_PROFILE:-}" ) ]]; then
  echo 'Release packages require Developer ID Installer and a notary keychain profile' >&2; exit 64
fi
scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ReKey.app/Contents/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/ReKey.app/Contents/Info.plist)"
package_filename="${1:-ReKey-${version}.pkg}"
if [[ "$package_filename" == */* || "$package_filename" != *.pkg ]]; then echo "Pass a .pkg filename without directories" >&2; exit 64; fi
final_output="build/$package_filename"
if [[ "$REKEY_RELEASE" == 1 && ( -e "$final_output" || -L "$final_output" ) ]]; then
  echo 'Refusing to overwrite an existing release package' >&2; exit 64
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/rekey-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
if [[ "$REKEY_RELEASE" == 1 ]]; then package_output="$stage/$package_filename"; else package_output="$final_output"; fi
mkdir -p "$stage/root/Applications" "$stage/scripts"
ditto --noextattr --noqtn --norsrc build/ReKey.app "$stage/root/Applications/ReKey.app"
/usr/bin/python3 - "$REKEY_PRODUCT_ID" "$stage/scripts/preinstall" <<'PYTHON'
from pathlib import Path
import sys
source = Path('Resources/pkg-preinstall').read_text()
assert source.count('@REKEY_CORE_LABEL@') == 1
Path(sys.argv[2]).write_text(source.replace('@REKEY_CORE_LABEL@', sys.argv[1] + '.core'))
PYTHON
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
if [[ "$REKEY_RELEASE" == 1 ]]; then
  /usr/bin/python3 scripts/verify-installer-signature.py "$package_output" "$REKEY_TEAM_ID"
fi
if [[ -n "${REKEY_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$package_output" --keychain-profile "$REKEY_NOTARY_PROFILE" --wait --output-format json > "$stage/notary-result.json"
  /usr/bin/python3 scripts/check-notary-result.py "$stage/notary-result.json"
  xcrun stapler staple "$package_output"
  xcrun stapler validate "$package_output"
  if [[ "$REKEY_RELEASE" == 1 ]]; then
    /usr/bin/python3 scripts/verify-installer-signature.py "$package_output" "$REKEY_TEAM_ID"
    spctl --assess --type install --verbose=2 "$package_output"
  fi
else
  echo "Development package: not notarized. Distribution requires Developer ID signing and notarization."
fi
if [[ "$REKEY_RELEASE" == 1 ]]; then
  mv -n "$package_output" "$final_output"
  [[ ! -e "$package_output" && -f "$final_output" ]] || { echo 'Could not place release package safely' >&2; exit 1; }
  echo "Release package verified: $final_output"
fi
