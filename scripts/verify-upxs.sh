#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: npm run verify:upxs -- deploy/langShot-x.y.z.upxs" >&2
  exit 1
fi

upxs_file="$1"
if [ ! -f "$upxs_file" ]; then
  echo "UPXS file does not exist: $upxs_file" >&2
  exit 1
fi

size_bytes="$(stat -f '%z' "$upxs_file")"
minimum_bytes=$((256 * 1024))
if [ "$size_bytes" -lt "$minimum_bytes" ]; then
  echo "UPXS is only ${size_bytes} bytes and likely omits langshot-helper.app. Repackage dist/langshot/plugin.json." >&2
  exit 1
fi

echo "UPXS size gate passed: $upxs_file (${size_bytes} bytes)"
shasum -a 256 "$upxs_file"
