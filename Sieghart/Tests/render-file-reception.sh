#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-file-receive.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"
source_root="Sieghart/Sieghart"
output="$repo_root/Sieghart/Design/Validation/file-reception"
sources=()
while IFS= read -r source_file; do sources+=("$source_file"); done < <(rg --files "$source_root/Shared/Components/Companion" "$source_root/Features/CompanionTeam" -g '*.swift' | sort)
sources+=("$source_root/Shared/Components/DesignSystem.swift" "$source_root/Shared/Components/Island/IslandChrome.swift"
  "$source_root/Shared/Models/AppearanceOptions.swift" "$source_root/Shared/Services/Tasks/CompanionEventCenter.swift" "Sieghart/Tests/CompanionRuntimePreview.swift")
xcrun swiftc -swift-version 6 -module-cache-path /private/tmp/sieghart-check-module-cache "${sources[@]}" -o "$check_dir/preview"
"$check_dir/preview" "$check_dir/output" --file-receive
mkdir -p "$output"
cp "$check_dir"/output/*-receive-*.png "$output/"
ffmpeg -hide_banner -loglevel error -y -framerate 60 -i "$check_dir/output/frames/%04d.png" -f lavfi -i 'color=c=black:s=512x512:r=60:d=2.6' -filter_complex '[1:v][0:v]overlay=shortest=1:format=auto,format=yuv420p' -c:v libx264 -crf 17 -movflags +faststart "$output/toni-file-receive.mp4"
