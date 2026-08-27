#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
native_root="$project_root/native"
output_root="$project_root/build/native"
app_root="$output_root/langshot-helper.app"
arm_build="$native_root/.build-arm64"
x86_build="$native_root/.build-x86_64"

MACOSX_DEPLOYMENT_TARGET=10.15 swift build --package-path "$native_root" --scratch-path "$arm_build" -c release --arch arm64
MACOSX_DEPLOYMENT_TARGET=10.15 swift build --package-path "$native_root" --scratch-path "$x86_build" -c release --arch x86_64
arm_binary="$(MACOSX_DEPLOYMENT_TARGET=10.15 swift build --package-path "$native_root" --scratch-path "$arm_build" -c release --arch arm64 --show-bin-path)/langshot-helper"
x86_binary="$(MACOSX_DEPLOYMENT_TARGET=10.15 swift build --package-path "$native_root" --scratch-path "$x86_build" -c release --arch x86_64 --show-bin-path)/langshot-helper"

mkdir -p "$app_root/Contents/MacOS"
lipo -create "$arm_binary" "$x86_binary" -output "$app_root/Contents/MacOS/langshot-helper"
cp "$project_root/scripts/helper-Info.plist" "$app_root/Contents/Info.plist"

lipo -info "$app_root/Contents/MacOS/langshot-helper"
echo "Built Universal helper: $app_root"
