#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-artwork.XXXXXX)"
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
  "Sieghart/Tests/CompanionRuntimePreview.swift")
xcrun swiftc -swift-version 6 -module-cache-path /private/tmp/sieghart-check-module-cache \
  "${sources[@]}" -o "$check_dir/artwork-export"
"$check_dir/artwork-export" "$repo_root/$source_root/Shared/Resources/ProviderAssets.xcassets" --portraits
