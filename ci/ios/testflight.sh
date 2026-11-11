#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/toolchain.sh"

[[ "${GITHUB_ACTIONS:-}" == true ]] || fail "请从 GitHub Actions 的 iOS TestFlight 工作流执行。"
upload="${IOS_UPLOAD:-false}"
required=(IOS_RELEASE_BUNDLE_ID IOS_TEAM_ID IOS_CERTIFICATE_BASE64 IOS_CERTIFICATE_PASSWORD IOS_PROFILE_BASE64)
case "$upload" in
    true) required+=(ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_BASE64) ;;
    false) ;;
    *) fail "IOS_UPLOAD must be true or false." ;;
esac
for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || fail "缺少 testflight environment 配置 ${name}。"
done
[[ "$IOS_RELEASE_BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail "Invalid release bundle ID."
[[ "$IOS_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid Apple Team ID."
[[ "$GITHUB_RUN_NUMBER" =~ ^[1-9][0-9]{0,5}$ && "$GITHUB_RUN_NUMBER" -le 999899 &&
   "$GITHUB_RUN_ATTEMPT" =~ ^[1-9][0-9]?$ ]] ||
    fail "Run number or attempt exceeds the CFBundleVersion range."
# Keep all three numeric components within Apple's documented limits.
build_number="$((GITHUB_RUN_NUMBER / 100 + 1)).$((GITHUB_RUN_NUMBER % 100)).$GITHUB_RUN_ATTEMPT"

check_xcode
umask 077
work_dir="$(mktemp -d "${RUNNER_TEMP:?}/neurun-signing.XXXXXX")"
keychain="$work_dir/signing.keychain-db"
installed_profile=''
cleanup() {
    if [[ -n "$installed_profile" ]]; then
        rm -f "$installed_profile"
    fi
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$work_dir"
}
trap cleanup EXIT

decode() {
    printf '%s' "$1" | /usr/bin/base64 -D > "$2"
}
decode "$IOS_CERTIFICATE_BASE64" "$work_dir/distribution.p12"
decode "$IOS_PROFILE_BASE64" "$work_dir/distribution.mobileprovision"
security cms -D -i "$work_dir/distribution.mobileprovision" -o "$work_dir/profile.plist"

keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work_dir/distribution.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
# The hosted release runner is ephemeral. Limit discovery to this job's keychain.
security list-keychains -d user -s "$keychain"
security find-identity -v -p codesigning "$keychain" > "$work_dir/identities.txt"

# Verify the profile and select a certificate it permits before archiving.
python3 - "$work_dir" "$IOS_RELEASE_BUNDLE_ID" "$IOS_TEAM_ID" <<'PY'
from datetime import datetime, timezone
from hashlib import sha1
from pathlib import Path
import plistlib
import re
import sys
from uuid import UUID

work_dir = Path(sys.argv[1])
bundle_id, team_id = sys.argv[2:]
with (work_dir / "profile.plist").open("rb") as source:
    profile = plistlib.load(source)
entitlements = profile["Entitlements"]
application_ids = {f"{prefix}.{bundle_id}" for prefix in profile["ApplicationIdentifierPrefix"]}
if (
    team_id not in profile["TeamIdentifier"]
    or entitlements.get("application-identifier") not in application_ids
    or entitlements.get("get-task-allow") is not False
    or "ProvisionedDevices" in profile
    or profile.get("ProvisionsAllDevices")
    or "iOS" not in profile["Platform"]
    or profile["ExpirationDate"].replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc)
):
    sys.exit("Use a current App Store distribution profile for the release bundle ID and team.")

identities = (work_dir / "identities.txt").read_text()
installed = set(re.findall(r'^\s*\d+\) ([A-F0-9]{40}) "Apple Distribution:', identities, re.MULTILINE))
allowed = {sha1(certificate).hexdigest().upper() for certificate in profile["DeveloperCertificates"]}
matches = installed & allowed
if len(matches) != 1:
    sys.exit("The P12 must contain one valid Apple Distribution identity allowed by the profile.")

profile_uuid = str(UUID(profile["UUID"])).upper()
identity = matches.pop()
(work_dir / "profile-uuid").write_text(profile_uuid)
(work_dir / "identity").write_text(identity)
with (work_dir / "ExportOptions.plist").open("wb") as output:
    plistlib.dump({
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "signingCertificate": identity,
        "teamID": team_id,
        "provisioningProfiles": {bundle_id: profile_uuid},
        "manageAppVersionAndBuildNumber": False,
    }, output)
PY

profile_uuid="$(cat "$work_dir/profile-uuid")"
identity="$(cat "$work_dir/identity")"
profile_dir="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profile_dir"
profile_path="$profile_dir/$profile_uuid.mobileprovision"
[[ ! -e "$profile_path" ]] || fail "Provisioning profile already exists on this runner."
installed_profile="$profile_path"
cp "$work_dir/distribution.mobileprovision" "$installed_profile"

archive="$work_dir/Neurun.xcarchive"
xcodebuild -project "$IOS_PROJECT" -scheme Neurun -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$work_dir/DerivedData" \
    -archivePath "$archive" archive \
    NEURUN_BUNDLE_ID="$IOS_RELEASE_BUNDLE_ID" CURRENT_PROJECT_VERSION="$build_number" \
    DEVELOPMENT_TEAM="$IOS_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_IDENTITY="$identity" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid"

app="$archive/Products/Applications/Neurun.app"
codesign --verify --strict "$app"
app_info="$app/Info.plist"
[[ "$(plutil -extract CFBundleIdentifier raw "$app_info")" == "$IOS_RELEASE_BUNDLE_ID" ]] ||
    fail "Archive bundle ID differs from the release configuration."
[[ "$(plutil -extract CFBundleVersion raw "$app_info")" == "$build_number" ]] ||
    fail "Archive build number differs from the CI build number."

xcodebuild -exportArchive -archivePath "$archive" -exportPath "$work_dir/export" \
    -exportOptionsPlist "$work_dir/ExportOptions.plist"
ipas=("$work_dir"/export/*.ipa)
[[ "${#ipas[@]}" -eq 1 && -f "${ipas[0]}" ]] || fail "Expected exactly one signed IPA."

record_dir="$RUNNER_TEMP/ios-release-record"
mkdir -p "$record_dir"
ditto -c -k --keepParent "$archive/dSYMs" "$record_dir/Neurun-dSYMs.zip"
version="$(plutil -extract CFBundleShortVersionString raw "$app_info")"
status='Signed export verified'
if [[ "$upload" == true ]]; then
    [[ "$ASC_KEY_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid App Store Connect key ID."
    key_path="$work_dir/AuthKey_$ASC_KEY_ID.p8"
    decode "$ASC_KEY_BASE64" "$key_path"
    xcrun altool --upload-app --type ios --file "${ipas[0]}" \
        --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --p8-file-path "$key_path"
    status='Upload accepted by Apple. Check build processing in App Store Connect.'
fi

{
    printf 'Commit: %s\nBundle ID: %s\nVersion: %s\nBuild: %s\n' \
        "$GITHUB_SHA" "$IOS_RELEASE_BUNDLE_ID" "$version" "$build_number"
    xcodebuild -version
    printf 'Result: %s\n' "$status"
} | tee "$record_dir/build.txt"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '### iOS release\n\n' >> "$GITHUB_STEP_SUMMARY"
    cat "$record_dir/build.txt" >> "$GITHUB_STEP_SUMMARY"
fi
