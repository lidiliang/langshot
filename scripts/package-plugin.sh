#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
dist_root="$project_root/dist/langshot"
helper_app="$project_root/build/native/langshot-helper.app"

if [ ! -x "$helper_app/Contents/MacOS/langshot-helper" ]; then
  echo "Universal helper is missing. Run: npm run build:native" >&2
  exit 1
fi

rm -rf "$dist_root"
mkdir -p "$dist_root/native"
cp -R "$project_root/plugin/." "$dist_root/"
cp -R "$helper_app" "$dist_root/native/"

"$project_root/scripts/verify-bundle.sh" "$dist_root"
