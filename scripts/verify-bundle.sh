#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle_root="${1:-$project_root/dist/langshot}"
manifest="$bundle_root/plugin.json"
helper_app="$bundle_root/native/langshot-helper.app"
helper_binary="$helper_app/Contents/MacOS/langshot-helper"
helper_info="$helper_app/Contents/Info.plist"

for required in "$manifest" "$bundle_root/index.html" "$bundle_root/preload.js" "$helper_binary" "$helper_info"; do
  if [ ! -f "$required" ]; then
    echo "Plugin bundle is incomplete; missing: $required" >&2
    exit 1
  fi
done

if [ ! -x "$helper_binary" ]; then
  echo "Bundled helper is not executable: $helper_binary" >&2
  exit 1
fi

node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$manifest"
plutil -lint "$helper_info" >/dev/null
lipo "$helper_binary" -verify_arch arm64 x86_64

size_kb="$(du -sk "$bundle_root" | awk '{print $1}')"
if [ "$size_kb" -gt 20480 ]; then
  echo "Plugin exceeds 20MB: ${size_kb}KB" >&2
  exit 1
fi

echo "Verified plugin bundle with Universal helper: $bundle_root (${size_kb}KB)"
