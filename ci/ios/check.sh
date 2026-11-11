#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/toolchain.sh"

command="${1:-doctor}"
case "$command" in
    doctor|open|boot|build|test|archive) ;;
    *) fail "用法: $0 {doctor|open|boot|build|test|archive}" ;;
esac

check_xcode
cd "$IOS_ROOT"

if [[ "$command" == doctor ]]; then
    xcodebuild -list -project "$IOS_PROJECT"
    xcodebuild -showsdks
    xcrun simctl list devices available
    printf '\nSimulator destination: %s\n' "$IOS_DESTINATION"
    exit 0
fi
if [[ "$command" == open ]]; then
    developer_dir="$(xcode-select -p)"
    xcode_app="$(cd "$developer_dir/../.." && pwd)"
    open -a "$xcode_app" "$IOS_PROJECT"
    exit 0
fi
if [[ "$command" == boot ]]; then
    simulator_id="$(xcrun simctl list devices available -j | python3 -c '
import json
import sys

name, version = sys.argv[1:]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + version.replace(".", "-")
devices = json.load(sys.stdin)["devices"].get(runtime, [])
for device in devices:
    if device["name"] == name:
        print(device["udid"])
        break
else:
    sys.exit(f"No available {name} simulator for iOS {version}")
' "$IOS_SIMULATOR_NAME" "$IOS_SIMULATOR_OS")"
    xcrun simctl bootstatus "$simulator_id" -b
    printf 'IOS_DESTINATION=platform=iOS Simulator,id=%s\n' "$simulator_id" >> "${GITHUB_ENV:?}"
    exit 0
fi

output_dir="${IOS_OUTPUT_DIR:-$IOS_ROOT/.build/ios}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
derived_data="$output_dir/DerivedData"
run_dir="$(mktemp -d "$output_dir/$command.XXXXXX")"
printf 'Build output: %s\n' "$run_dir"
arguments=(-project "$IOS_PROJECT" -scheme Neurun -derivedDataPath "$derived_data")
case "$command" in
    build)
        arguments+=(-configuration Debug -destination "$IOS_DESTINATION")
        signing=(CODE_SIGN_IDENTITY=-)
        ;;
    test)
        arguments+=(-configuration Debug -destination "$IOS_DESTINATION" -parallel-testing-enabled NO
            -resultBundlePath "$run_dir/Neurun.xcresult")
        signing=(CODE_SIGN_IDENTITY=-)
        ;;
    archive)
        arguments+=(-configuration Release -destination 'generic/platform=iOS'
            -archivePath "$run_dir/Neurun.xcarchive"
            -resultBundlePath "$run_dir/Neurun.xcresult")
        signing=(CODE_SIGNING_ALLOWED=NO)
        ;;
esac
xcodebuild "${arguments[@]}" "$command" "${signing[@]}" 2>&1 | tee "$run_dir/xcodebuild.log"

if [[ "$command" == archive ]]; then
    test -f "$run_dir/Neurun.xcarchive/Products/Applications/Neurun.app/Info.plist"
fi
