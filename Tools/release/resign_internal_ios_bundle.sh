#!/bin/bash
set -euo pipefail

# Re-sign an already checksum-verified unsigned iOS bundle for one approved
# internal iPhone + paired Watch target, or one approved iPad target. Profiles
# and private keys stay local.

if test "$#" -ne 3 && test "$#" -ne 4; then
  echo "usage: $0 <DJConnect.app> <signing-identity> <ios-device-udid> [watch-udid]" >&2
  exit 64
fi

app_bundle="$1"
signing_identity="$2"
ios_device_udid="$3"
watch_udid="${4:-}"

test -d "$app_bundle"
security find-identity -v -p codesigning | grep -F -- "$signing_identity" >/dev/null

profiles=(
  "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  "$HOME/Library/MobileDevice/Provisioning Profiles"
)
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

sign_bundle() {
  local bundle="$1" identifier required_udid profile decoded entitlements
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Info.plist")"
  required_udid="$ios_device_udid"
  if [[ "$identifier" == *".watch"* ]]; then
    test -n "$watch_udid" || { echo "watch bundle found without an approved Watch UDID" >&2; exit 1; }
    required_udid="$watch_udid"
  fi
  profile="$(/usr/bin/python3 "$script_dir/select_internal_ios_profile.py" \
    "$identifier" "$required_udid" "$signing_identity" "${profiles[@]}")"
  decoded="$scratch/${identifier}.profile.plist"
  entitlements="$scratch/${identifier}.entitlements.plist"
  security cms -D -i "$profile" > "$decoded"
  plutil -extract Entitlements xml1 -o "$entitlements" "$decoded"
  if [[ "$identifier" = dev.djconnect.ios ]]; then
    # A provisioning profile lists allowed values. The signed application
    # requests a single App Attest environment, matching the iOS target.
    /usr/bin/python3 - "$entitlements" <<'PYTHON'
import plistlib
from pathlib import Path
import sys

path = Path(sys.argv[1])
values = plistlib.loads(path.read_bytes())
key = "com.apple.developer.devicecheck.appattest-environment"
provided = values.get(key)
if provided != "development" and not (
    isinstance(provided, list) and "development" in provided
):
    raise SystemExit("The selected iOS profile does not allow App Attest development")
values[key] = "development"
path.write_bytes(plistlib.dumps(values))
PYTHON
  fi
  cp "$profile" "$bundle/embedded.mobileprovision"
  /usr/bin/codesign --force --sign "$signing_identity" --entitlements "$entitlements" --timestamp=none --generate-entitlement-der "$bundle"
  case "$identifier" in
    dev.djconnect.ios|dev.djconnect.ios.watch)
      /usr/bin/codesign -d --entitlements - --xml "$bundle" > "$scratch/signed.plist"
      test "$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$scratch/signed.plist")" = development
      if [[ "$identifier" = dev.djconnect.ios ]]; then
        test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.devicecheck.appattest-environment' "$scratch/signed.plist")" = development
      fi
      ;;
  esac
}

find "$app_bundle" -name '._*' -type f -delete
xattr -cr "$app_bundle"
if test -z "$watch_udid"; then
  # An iPad is a standalone internal target. Do not sign or ship the embedded
  # Watch companion without an explicitly approved paired Watch device.
  rm -rf "$app_bundle/Watch"
fi
find "$app_bundle" -type d -name '*.framework' -print0 | while IFS= read -r -d '' framework; do
  /usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$framework"
done
find "$app_bundle" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' library; do
  /usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$library"
done
find "$app_bundle" \( -name '*.app' -o -name '*.appex' \) -type d -depth -print0 | while IFS= read -r -d '' bundle; do
  sign_bundle "$bundle"
done
/usr/bin/codesign --verify --deep --strict "$app_bundle"
