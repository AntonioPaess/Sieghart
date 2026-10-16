#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-render-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"
source_root="Sieghart/Sieghart"
sources=()
while IFS= read -r source_file; do sources+=("$source_file"); done < <(
  rg --files "$source_root/Shared/Components/Companion" "$source_root/Features/CompanionTeam" -g '*.swift' | sort
)
sources+=("$source_root/Shared/Components/DesignSystem.swift"
  "$source_root/Shared/Components/Island/IslandChrome.swift"
  "$source_root/Shared/Models/AppearanceOptions.swift"
  "$source_root/Shared/Services/Tasks/CompanionEventCenter.swift"
  "Sieghart/Tests/CompanionPerformanceChecks.swift")

# Real offscreen Metal rendering in Debug, with API validation. No app windows
# or resident services are constructed. This is separate from hardware-free
# unit checks because it needs a Metal-capable Mac and takes about a minute.
xcrun swiftc -Onone -swift-version 6 -module-cache-path /private/tmp/sieghart-check-module-cache \
  "${sources[@]}" -o "$check_dir/companion-render-checks"
MTL_DEBUG_LAYER=1 "$check_dir/companion-render-checks"
