#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 && $# -ne 3 ]]; then
  echo "usage: smoke_installed_macos_app.sh VERSION HOST_UUID [BUILD]" >&2
  exit 2
fi

expected_version=$1
expected_uuid=$2
expected_build=${3:-}
[[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 2
[[ "$expected_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || exit 2

observed_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4; exit}')
[[ "$observed_uuid" == "$expected_uuid" ]] || { echo "unexpected smoke host" >&2; exit 1; }
app_path="$HOME/Applications/DJConnect.app"
[[ -d "$app_path" && ! -L "$app_path" ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")" == dev.djconnect.mac ]] || exit 1
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")" == "$expected_version" ]] || exit 1
if [[ -n "$expected_build" ]]; then
  [[ "$expected_build" =~ ^[1-9][0-9]*$ ]] || exit 2
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")" == "$expected_build" ]] || exit 1
fi
codesign --verify --deep --strict "$app_path"
open -gj "$app_path"
for attempt in 1 2 3 4 5; do
  pgrep -x DJConnect >/dev/null && exit 0
  sleep 2
done
echo "DJConnect did not launch" >&2
exit 1
