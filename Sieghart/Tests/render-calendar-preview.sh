#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"
sources=()
while IFS= read -r source_file; do sources+=("$source_file"); done < <(
  rg --files Sieghart/Sieghart -g '*.swift' | sort | sed '/\/App\//d'
)
# Injected adapters and an offscreen ImageRenderer only. No native app windows,
# EventKit reads, permission prompts, keyboard hooks or live hardware.
xcrun swiftc -swift-version 6 -module-cache-path /private/tmp/sieghart-check-module-cache \
  "${sources[@]}" Sieghart/Tests/CalendarPreview.swift -o /private/tmp/sieghart-calendar-preview
/private/tmp/sieghart-calendar-preview "${1:-/private/tmp/sieghart-team-build/Build/Products/Debug/Sieghart.app}"
