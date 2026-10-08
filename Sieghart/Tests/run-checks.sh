#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check_dir="$(mktemp -d /private/tmp/sieghart-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
cd "$repo_root"
source_root="Sieghart/Sieghart"
module_cache="${CLANG_MODULE_CACHE_PATH:-/private/tmp/sieghart-check-module-cache}"

# Resolve feature/Core/Shared sources once. App composition is excluded so
# isolated checks never construct the resident app or start platform services.
all_sources=()
while IFS= read -r source_file; do all_sources+=("$source_file"); done < <(rg --files "$source_root" -g '*.swift' | sort | sed '/\/App\//d')
ui_shared=("$source_root/Shared/Components/DesignSystem.swift" "$source_root/Shared/Components/Island/IslandChrome.swift"
  "$source_root/Shared/Components/Companion/CompanionAvatars.swift" "$source_root/Shared/Components/Companion/CompanionArrival.swift"
  "$source_root/Shared/Models/AppearanceOptions.swift" "$source_root/Shared/Services/Preferences/CompanionPreferences.swift")
codex_sources=("$source_root/Core/Services/AI/CodexUsage.swift" "$source_root/Features/AIUsage/ViewModels/CodexUsageViewModel.swift")
ai_sources=("${codex_sources[@]}" "$source_root/Core/Services/AI/ModelPricing.swift"
  "$source_root/Core/Services/AI/AIUsage.swift" "$source_root/Core/Services/AI/UsageImports.swift"
  "$source_root/Core/Services/AI/AIActivity.swift" "$source_root/Features/AIUsage/ViewModels/AIUsageViewModel.swift")
clipboard_sources=("$source_root/Core/Services/Clipboard/ClipboardHistory.swift" "$source_root/Features/Clipboard/ViewModels/ClipboardViewModel.swift")
check() {
  local check_name="$1"; shift
  xcrun swiftc -swift-version 6 -module-cache-path "$module_cache" "$@" -o "$check_dir/$check_name"
  "$check_dir/$check_name"
}

check timer "$source_root/Core/Helpers/TimerModels.swift" "$source_root/Features/Timers/ViewModels/AssistantViewModel.swift" \
  "$source_root/Core/Services/Input/SensorEngine.swift" "$source_root/Features/ImpactGestures/ViewModels/SensorViewModel.swift" Sieghart/Tests/PomodoroChecks.swift
check callbacks "$source_root/Core/Services/Voice/VoiceCapture.swift" Sieghart/Tests/VoiceCallbackChecks.swift
check interactions "${all_sources[@]}" Sieghart/Tests/InteractionChecks.swift
check usage "${codex_sources[@]}" Sieghart/Tests/CodexUsageChecks.swift
check spending "${ai_sources[@]}" Sieghart/Tests/TokenSpendingChecks.swift
check activity "${ai_sources[@]}" "${ui_shared[@]}" Sieghart/Tests/AIActivityChecks.swift
check pricing "${ai_sources[@]}" Sieghart/Tests/PricingChecks.swift
check audio "$source_root/Core/Services/Audio/AudioEngine.swift" "$source_root/Features/Audio/ViewModels/AudioViewModel.swift" Sieghart/Tests/AudioChecks.swift
check imports "${ai_sources[@]}" Sieghart/Tests/UsageImportChecks.swift
check clipboard "${clipboard_sources[@]}" "${ui_shared[@]}" Sieghart/Tests/ClipboardChecks.swift
check middle-click "$source_root/Shared/Services/Input/MiddleClickController.swift" Sieghart/Tests/MiddleClickChecks.swift
check utilities "$source_root/Core/Services/System/MacSystemSampler.swift" "$source_root/Features/SystemMonitor/ViewModels/SystemMonitorViewModel.swift" \
  "$source_root/Core/Services/Power/MacAwakeBackend.swift" "$source_root/Features/KeepAwake/ViewModels/KeepAwakeViewModel.swift" \
  "$source_root/Core/Services/Display/MacDisplayPowerBackend.swift" "$source_root/Features/DisplayPower/ViewModels/DisplayPowerViewModel.swift" Sieghart/Tests/UtilityChecks.swift
