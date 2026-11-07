#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/build-config.sh
scripts/build-core.sh
scripts/build-icons.sh
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/build/ReKey.app"
version="${REKEY_VERSION:-0.1.0}"
if [[ ! "$version" =~ '^[0-9]+([.][0-9]+){1,2}$' ]]; then echo "REKEY_VERSION must be a numeric dotted version" >&2; exit 64; fi
if [[ -n "${REKEY_FEED_URL:-}" || -n "${REKEY_ED_PUBLIC_KEY:-}" ]]; then
  [[ -n "${REKEY_FEED_URL:-}" && -n "${REKEY_ED_PUBLIC_KEY:-}" ]] || { echo "Feed URL and EdDSA public key must be supplied together" >&2; exit 64; }
  /usr/bin/python3 - "$REKEY_FEED_URL" "$REKEY_ED_PUBLIC_KEY" <<'PYTHON'
import base64, sys, urllib.parse
try:
    url = urllib.parse.urlparse(sys.argv[1])
    assert url.scheme == 'https' and url.hostname and not url.username and not url.password
    assert len(base64.b64decode(sys.argv[2], validate=True)) == 32
except Exception:
    sys.exit('Invalid HTTPS feed URL or EdDSA public key')
PYTHON
fi
rm -rf "$app"
build_number="${REKEY_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
case "$build_number" in ''|*[!0-9]*) echo "REKEY_BUILD_NUMBER must be a positive integer" >&2; exit 64;; esac
if [[ "$build_number" -lt 1 ]]; then echo "REKEY_BUILD_NUMBER must be a positive integer" >&2; exit 64; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/ReKey" "$app/Contents/MacOS/ReKey"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp build/AppIcon.icns Resources/Icons/Menu*.pdf "$app/Contents/Resources/"
mkdir -p "$app/Contents/Resources/Licenses"
ditto Resources/Licenses "$app/Contents/Resources/Licenses"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Licenses/Sparkle.txt"
cp Vendor/VirtualHID/LICENSE.md "$app/Contents/Resources/Licenses/Karabiner-DriverKit-VirtualHIDDevice.txt"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $REKEY_PRODUCT_ID" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
if [[ -n "${REKEY_FEED_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $REKEY_FEED_URL" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $REKEY_ED_PUBLIC_KEY" "$app/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c 'Add :SURequireSignedFeed bool true' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAllowsAutomaticUpdates bool false' "$app/Contents/Info.plist"
framework_source="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
ditto "$framework_source" "$app/Contents/Frameworks/Sparkle.framework"
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_args=(--force --sign "${REKEY_SIGNING_IDENTITY:--}" --options runtime)
codesign "${sign_args[@]}" "$framework/XPCServices/Installer.xpc"
codesign "${sign_args[@]}" --preserve-metadata=entitlements "$framework/XPCServices/Downloader.xpc"
codesign "${sign_args[@]}" "$framework/Autoupdate"
codesign "${sign_args[@]}" "$framework/Updater.app"
codesign "${sign_args[@]}" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$app/Contents/MacOS/ReKey"
ditto Resources/en.lproj "$app/Contents/Resources/en.lproj"
ditto Resources/ja.lproj "$app/Contents/Resources/ja.lproj"
agent="$app/Contents/Library/LoginItems/ReKeyAgent.app"
mkdir -p "$agent/Contents/MacOS" "$agent/Contents/Resources" "$app/Contents/Library/LaunchAgents"
cp "$binary_dir/ReKeyAgent" "$agent/Contents/MacOS/ReKeyAgent"
cp Resources/Info.plist "$agent/Contents/Info.plist"
cp build/AppIcon.icns "$agent/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ReKeyAgent' "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${REKEY_PRODUCT_ID}.agent" "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ReKeyAgent' "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ReKey Agent' "$agent/Contents/Info.plist"
cp Resources/jp.example.rekey.agent.plist "$app/Contents/Library/LaunchAgents/"
codesign "${sign_args[@]}" "$agent"
if [[ -f build/rekey-core ]]; then
  mkdir -p "$app/Contents/Library/LaunchDaemons" "$app/Contents/Library/HelperTools"
  rm -f "$app/Contents/Library/HelperTools/rekey-vhid"
  cp build/rekey-core build/rekey-bench "$app/Contents/Library/HelperTools/"
  rm -f "$app/Contents/Library/LaunchDaemons/jp.example.rekey.agent.plist"
  cp Resources/jp.example.rekey.core.plist Resources/jp.example.rekey.vhid.plist "$app/Contents/Library/LaunchDaemons/"
  cp Vendor/VirtualHID/files/LaunchDaemons/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist "$app/Contents/Library/LaunchDaemons/"
  codesign "${sign_args[@]}" "$app/Contents/Library/HelperTools/rekey-core"
  codesign "${sign_args[@]}" "$app/Contents/Library/HelperTools/rekey-bench"
fi
codesign "${sign_args[@]}" "$app"
if [[ -n "${REKEY_TEAM_ID:-}" ]]; then
  for signed in "$app" "$agent" "$app/Contents/Library/HelperTools/rekey-core"; do
    team=$(codesign -dv "$signed" 2>&1 | /usr/bin/awk -F= '$1 == "TeamIdentifier" { print $2 }')
    [[ "$team" == "$REKEY_TEAM_ID" ]] || { echo "Signing Team ID mismatch: $signed" >&2; exit 1; }
  done
fi
echo "$app"
