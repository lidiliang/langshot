#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dist_root="$project_root/dist/langshot"

rm -rf "$dist_root"
mkdir -p "$dist_root/native"
cp -R "$project_root/plugin/." "$dist_root/"
cp -R "$project_root/build/native/langshot-helper.app" "$dist_root/native/"

size_kb="$(du -sk "$dist_root" | awk '{print $1}')"
if [ "$size_kb" -gt 20480 ]; then
  echo "Plugin exceeds 20MB: ${size_kb}KB" >&2
  exit 1
fi

echo "Packaged $dist_root (${size_kb}KB)"

