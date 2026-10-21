#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build-app.sh
package_filename="${1:-ReKey-0.1.0.pkg}"
if [[ "$package_filename" == */* || "$package_filename" != *.pkg ]]; then echo "Pass a .pkg filename without directories" >&2; exit 64; fi
package_output="build/$package_filename"
stage=$(mktemp -d "${TMPDIR:-/tmp}/rekey-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/root/Applications" "$stage/scripts"
ditto --noextattr --noqtn --norsrc build/ReKey.app "$stage/root/Applications/ReKey.app"
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
args=(--component-plist "$stage/components.plist" --root "$stage/root" --scripts "$stage/scripts" --identifier jp.example.rekey.pkg --version 0.1.0 --install-location / --ownership recommended)
if [[ -n "${REKEY_INSTALLER_IDENTITY:-}" ]]; then args+=(--sign "$REKEY_INSTALLER_IDENTITY"); fi
pkgbuild "${args[@]}" "$package_output"
if [[ -n "${REKEY_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$package_output" --keychain-profile "$REKEY_NOTARY_PROFILE" --wait
  xcrun stapler staple "$package_output"
else
  echo "Development package: not notarized. Distribution requires Developer ID signing and notarization."
fi
