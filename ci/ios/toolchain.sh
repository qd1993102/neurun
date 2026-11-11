#!/bin/bash

IOS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IOS_PROJECT="$IOS_ROOT/apps/ios/Neurun.xcodeproj"
IOS_XCODE_VERSION="$(cat "$IOS_ROOT/.xcode-version")"
IOS_SIMULATOR_NAME='iPhone 17'
IOS_SIMULATOR_OS='26.5'
IOS_DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=$IOS_SIMULATOR_NAME,OS=$IOS_SIMULATOR_OS}"

# Prefer the named Xcode, without changing the machine's global xcode-select.
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode_${IOS_XCODE_VERSION}.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode_${IOS_XCODE_VERSION}.app/Contents/Developer"
elif [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

fail() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

check_xcode() {
    local version_output
    if ! version_output="$(xcodebuild -version 2>&1)"; then
        fail "完整 Xcode $IOS_XCODE_VERSION 不可用。安装 Xcode 或设置 DEVELOPER_DIR。$version_output"
    fi
    if [[ "${version_output%%$'\n'*}" != "Xcode $IOS_XCODE_VERSION" ]]; then
        fail "项目使用 Xcode $IOS_XCODE_VERSION，当前为 ${version_output%%$'\n'*}。请设置 DEVELOPER_DIR。"
    fi
    printf '%s\n' "$version_output"
}
