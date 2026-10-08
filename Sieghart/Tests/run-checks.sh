#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" \
  Sieghart/Sieghart/AssistantCore.swift Sieghart/Sieghart/SensorEngine.swift \
  Sieghart/Tests/PomodoroChecks.swift -o "$check_dir/timer"
"$check_dir/timer"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" \
  Sieghart/Sieghart/VoiceCallbacks.swift Sieghart/Tests/VoiceCallbackChecks.swift \
  -o "$check_dir/callbacks"
"$check_dir/callbacks"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" \
  Sieghart/Sieghart/AssistantCore.swift Sieghart/Sieghart/SensorEngine.swift \
  Sieghart/Sieghart/IslandChrome.swift Sieghart/Sieghart/DesignSystem.swift Sieghart/Sieghart/CompanionAvatars.swift Sieghart/Sieghart/CompanionArrival.swift \
  Sieghart/Sieghart/MiddleClick.swift Sieghart/Sieghart/ClipboardHistory.swift Sieghart/Sieghart/ClipboardHistoryView.swift Sieghart/Sieghart/NotchWidget.swift Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Sieghart/CodexUsageView.swift Sieghart/Sieghart/ModelPricing.swift Sieghart/Sieghart/AIUsage.swift Sieghart/Sieghart/UsageImports.swift Sieghart/Sieghart/AIUsageView.swift \
  Sieghart/Sieghart/AIActivity.swift Sieghart/Sieghart/AIActivityView.swift Sieghart/Sieghart/OnboardingView.swift \
  Sieghart/Sieghart/ActivationCore.swift Sieghart/Sieghart/KeyboardShortcuts.swift \
  Sieghart/Sieghart/VoiceCommands.swift Sieghart/Sieghart/VoiceCallbacks.swift \
  Sieghart/Sieghart/AudioEngine.swift Sieghart/Sieghart/AudioControlsView.swift \
  Sieghart/Sieghart/FocusSessionView.swift Sieghart/Tests/InteractionChecks.swift \
  -o "$check_dir/interactions"
"$check_dir/interactions"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Tests/CodexUsageChecks.swift -o "$check_dir/usage"
"$check_dir/usage"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Sieghart/ModelPricing.swift Sieghart/Sieghart/AIUsage.swift Sieghart/Sieghart/UsageImports.swift Sieghart/Sieghart/AIActivity.swift Sieghart/Tests/TokenSpendingChecks.swift \
  -o "$check_dir/spending"
"$check_dir/spending"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Sieghart/ModelPricing.swift Sieghart/Sieghart/AIUsage.swift Sieghart/Sieghart/UsageImports.swift Sieghart/Sieghart/AIActivity.swift \
  Sieghart/Sieghart/IslandChrome.swift Sieghart/Sieghart/DesignSystem.swift Sieghart/Sieghart/CompanionAvatars.swift Sieghart/Sieghart/CompanionArrival.swift \
  Sieghart/Tests/AIActivityChecks.swift -o "$check_dir/activity"
"$check_dir/activity"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Sieghart/ModelPricing.swift Sieghart/Sieghart/AIUsage.swift Sieghart/Sieghart/UsageImports.swift \
  Sieghart/Sieghart/AIActivity.swift Sieghart/Tests/PricingChecks.swift -o "$check_dir/pricing"
"$check_dir/pricing"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/AudioEngine.swift \
  Sieghart/Tests/AudioChecks.swift -o "$check_dir/audio"
"$check_dir/audio"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" Sieghart/Sieghart/CodexUsage.swift \
  Sieghart/Sieghart/ModelPricing.swift Sieghart/Sieghart/AIUsage.swift \
  Sieghart/Sieghart/AIActivity.swift Sieghart/Sieghart/UsageImports.swift \
  Sieghart/Tests/UsageImportChecks.swift -o "$check_dir/imports"
"$check_dir/imports"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" \
  Sieghart/Sieghart/ClipboardHistory.swift Sieghart/Sieghart/CompanionArrival.swift \
  Sieghart/Sieghart/CompanionAvatars.swift Sieghart/Sieghart/DesignSystem.swift Sieghart/Sieghart/IslandChrome.swift \
  Sieghart/Tests/ClipboardChecks.swift -o "$check_dir/clipboard"
"$check_dir/clipboard"

xcrun swiftc -swift-version 6 -module-cache-path "${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}" \
  Sieghart/Sieghart/MiddleClick.swift Sieghart/Tests/MiddleClickChecks.swift -o "$check_dir/middle-click"
"$check_dir/middle-click"
