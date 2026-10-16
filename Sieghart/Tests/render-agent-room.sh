#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
sources=()
while IFS= read -r source_file; do sources+=("$source_file"); done < <(rg --files Sieghart/Sieghart -g '*.swift' | sort | sed '/\/App\//d')
xcrun swiftc -swift-version 6 -module-cache-path /private/tmp/sieghart-check-module-cache \
  "${sources[@]}" Sieghart/Tests/PlatformFixtures.swift Sieghart/Tests/AgentRoomPreview.swift -o /private/tmp/sieg-room-preview
/private/tmp/sieg-room-preview "${1:-/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app}"
