#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
native_root="$project_root/native"
output_root="$project_root/build/native"
app_root="$output_root/langshot-helper.app"

swift build --package-path "$native_root" -c release
binary_path="$(swift build --package-path "$native_root" -c release --show-bin-path)/langshot-helper"

mkdir -p "$app_root/Contents/MacOS"
cp "$binary_path" "$app_root/Contents/MacOS/langshot-helper"
cp "$project_root/scripts/helper-Info.plist" "$app_root/Contents/Info.plist"

echo "Built $app_root"

