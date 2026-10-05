#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"

xcrun swiftc -swift-version 6 \
  Sieghart/Sieghart/AssistantCore.swift Sieghart/Sieghart/SensorEngine.swift \
  Sieghart/Tests/PomodoroChecks.swift -o "$check_dir/timer"
"$check_dir/timer"

xcrun swiftc -swift-version 6 \
  Sieghart/Sieghart/VoiceCallbacks.swift Sieghart/Tests/VoiceCallbackChecks.swift \
  -o "$check_dir/callbacks"
"$check_dir/callbacks"

xcrun swiftc -swift-version 6 \
  Sieghart/Sieghart/AssistantCore.swift Sieghart/Sieghart/SensorEngine.swift \
  Sieghart/Sieghart/DesignSystem.swift Sieghart/Sieghart/NotchWidget.swift \
  Sieghart/Sieghart/ActivationCore.swift Sieghart/Sieghart/KeyboardShortcuts.swift \
  Sieghart/Sieghart/VoiceCommands.swift Sieghart/Sieghart/VoiceCallbacks.swift \
  Sieghart/Sieghart/FocusSessionView.swift Sieghart/Tests/InteractionChecks.swift \
  -o "$check_dir/interactions"
"$check_dir/interactions"
