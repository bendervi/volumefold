#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
preview_dir="${TMPDIR:-/tmp}/volumefold-preview"
mkdir -p "$preview_dir"
xcrun swiftc -parse-as-library Sources/VolumeFoldCore/*.swift \
  Sources/VolumeFoldApp/AppSettings.swift Sources/VolumeFoldApp/VolumeFoldMenu.swift \
  scripts/render-menu.swift -o "$preview_dir/render-menu"
"$preview_dir/render-menu" "$preview_dir"
echo "Previews: $preview_dir"
