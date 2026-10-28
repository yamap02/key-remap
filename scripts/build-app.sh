#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
scripts/build-core.sh
scripts/build-icons.sh
swift build -c release
binary_dir=$(swift build -c release --show-bin-path)
app="$PWD/build/ReKey.app"
build_number="${REKEY_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
case "$build_number" in ''|*[!0-9]*) echo "REKEY_BUILD_NUMBER must be a positive integer" >&2; exit 64;; esac
if [[ "$build_number" -lt 1 ]]; then echo "REKEY_BUILD_NUMBER must be a positive integer" >&2; exit 64; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/ReKey" "$app/Contents/MacOS/ReKey"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp build/AppIcon.icns Resources/Icons/Menu*.pdf "$app/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
ditto Resources/en.lproj "$app/Contents/Resources/en.lproj"
ditto Resources/ja.lproj "$app/Contents/Resources/ja.lproj"
agent="$app/Contents/Library/LoginItems/ReKeyAgent.app"
mkdir -p "$agent/Contents/MacOS" "$agent/Contents/Resources" "$app/Contents/Library/LaunchAgents"
cp "$binary_dir/ReKeyAgent" "$agent/Contents/MacOS/ReKeyAgent"
cp Resources/Info.plist "$agent/Contents/Info.plist"
cp build/AppIcon.icns "$agent/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable ReKeyAgent' "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier jp.example.rekey.agent' "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName ReKeyAgent' "$agent/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName ReKey Agent' "$agent/Contents/Info.plist"
cp Resources/jp.example.rekey.agent.plist "$app/Contents/Library/LaunchAgents/"
codesign --force --sign "${REKEY_SIGNING_IDENTITY:--}" "$agent"
if [[ -f build/rekey-core ]]; then
  mkdir -p "$app/Contents/Library/LaunchDaemons" "$app/Contents/Library/HelperTools"
  rm -f "$app/Contents/Library/HelperTools/rekey-vhid"
  cp build/rekey-core build/rekey-bench "$app/Contents/Library/HelperTools/"
  rm -f "$app/Contents/Library/LaunchDaemons/jp.example.rekey.agent.plist"
  cp Resources/jp.example.rekey.core.plist Resources/jp.example.rekey.vhid.plist "$app/Contents/Library/LaunchDaemons/"
  cp Vendor/VirtualHID/files/LaunchDaemons/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist "$app/Contents/Library/LaunchDaemons/"
  codesign --force --sign "${REKEY_SIGNING_IDENTITY:--}" "$app/Contents/Library/HelperTools/rekey-core"
  codesign --force --sign "${REKEY_SIGNING_IDENTITY:--}" "$app/Contents/Library/HelperTools/rekey-bench"
fi
codesign --force --sign "${REKEY_SIGNING_IDENTITY:--}" "$app"
echo "$app"
