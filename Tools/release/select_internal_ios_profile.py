"""Select a valid development profile for the approved Apple relay target."""
import hashlib
import plistlib
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def select_profile(profiles, bundle_id, device, signing_identity, now):
    exact, wildcard = [], []
    for path, profile in profiles:
        entitlements = profile.get("Entitlements", {})
        identifier = entitlements.get("application-identifier", "")
        _, separator, allowed_bundle = identifier.partition(".")
        expiry = profile.get("ExpirationDate")
        if isinstance(expiry, datetime) and expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        if (
            not separator
            or not isinstance(expiry, datetime)
            or expiry <= now
            or entitlements.get("get-task-allow") is not True
            or device not in profile.get("ProvisionedDevices", [])
            or not any(hashlib.sha1(cert).hexdigest().upper() == signing_identity
                       for cert in profile.get("DeveloperCertificates", []) if isinstance(cert, bytes))
        ):
            continue
        if allowed_bundle == bundle_id:
            exact.append((expiry, path, entitlements))
        elif allowed_bundle.endswith("*") and bundle_id.startswith(allowed_bundle[:-1]):
            wildcard.append((expiry, path, entitlements))

    candidates = exact or wildcard
    if not candidates:
        raise ValueError(f"No current development profile for {bundle_id} covering the approved device and signing identity")
    if any(entitlements != candidates[0][2] for _, _, entitlements in candidates):
        raise ValueError(f"Conflicting development profile entitlements for {bundle_id}")
    return max(candidates, key=lambda candidate: (candidate[0], str(candidate[1])))[1]


def read_profiles(directories):
    for directory in directories:
        if not directory.is_dir():
            continue
        for path in directory.iterdir():
            if not path.is_file() or path.suffix not in {".mobileprovision", ".provisionprofile"}:
                continue
            try:
                decoded = subprocess.run(
                    ["security", "cms", "-D", "-i", str(path)],
                    capture_output=True, check=True, timeout=10,
                ).stdout
                profile = plistlib.loads(decoded)
            except (subprocess.SubprocessError, plistlib.InvalidFileException):
                continue
            yield path, profile


if __name__ == "__main__":
    bundle, device, identity, *directories = sys.argv[1:]
    if not re.fullmatch(r"[0-9a-fA-F]{40}", identity):
        raise SystemExit("Expected the configured Apple Development signing certificate fingerprint")
    try:
        print(select_profile(
            read_profiles(map(Path, directories)), bundle, device, identity.upper(),
            datetime.now(timezone.utc),
        ))
    except ValueError as error:
        raise SystemExit(str(error))
